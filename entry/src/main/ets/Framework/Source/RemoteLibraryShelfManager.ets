import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ImageSourceType, Manga } from '../../Models/MangaModels';
import { DataService } from '../Services/DataService';
import { LibraryCoverManager, LibraryCoverType } from 'manxia_core/src/main/ets/Framework/Storage/LibraryCoverManager';
import { RemoteLibraryMangaBridge } from './RemoteLibraryMangaBridge';

const TAG = 'RemoteLibraryShelfManager';

export class RemoteLibraryShelfManager {
  private static instance: RemoteLibraryShelfManager | null = null;

  private readonly dataService: DataService = DataService.getInstance();
  private readonly remoteLibraryBridge: RemoteLibraryMangaBridge = RemoteLibraryMangaBridge.getInstance();

  private constructor() {
  }

  public static getInstance(): RemoteLibraryShelfManager {
    if (RemoteLibraryShelfManager.instance === null) {
      RemoteLibraryShelfManager.instance = new RemoteLibraryShelfManager();
    }
    return RemoteLibraryShelfManager.instance;
  }

  public async isInLocalLibrary(mangaId: string): Promise<boolean> {
    return this.dataService.isFavorited(mangaId);
  }

  public async addToLocalLibrary(manga: Manga, filesDir: string): Promise<Manga> {
    const nextManga: Manga = this.cloneManga(manga);
    const persistedCoverPath = await this.persistCover(nextManga, filesDir);
    const now = Date.now();

    nextManga.isFavorite = true;
    nextManga.addedToLibraryAt = nextManga.addedToLibraryAt && nextManga.addedToLibraryAt > 0
      ? nextManga.addedToLibraryAt
      : now;
    nextManga.lastUpdatedAt = now;

    if (persistedCoverPath.length > 0) {
      nextManga.coverImagePath = persistedCoverPath;
      nextManga.coverSourceType = ImageSourceType.LOCAL;
    }

    await this.dataService.addToFavorites(nextManga.id);
    await this.remoteLibraryBridge.upsertLocalLibraryManga(nextManga);
    logger.info(TAG, `已加入本地书架: ${nextManga.id}`);
    return nextManga;
  }

  public async removeFromLocalLibrary(manga: Manga, filesDir: string): Promise<void> {
    const normalizedCoverPath = LibraryCoverManager.normalizeLocalPath(manga.coverImagePath || '');
    await this.dataService.removeFromFavorites(manga.id);
    await this.remoteLibraryBridge.removeLocalLibraryManga(manga.id);

    if (normalizedCoverPath.length > 0) {
      LibraryCoverManager.deleteManagedCoverIfExists(normalizedCoverPath, filesDir);
    }

    logger.info(TAG, `已从本地书架移除: ${manga.id}`);
  }

  private async persistCover(manga: Manga, filesDir: string): Promise<string> {
    const sourceCover = String(manga.coverImagePath || '').trim();
    if (sourceCover.length <= 0 || filesDir.length <= 0) {
      return '';
    }

    const providerKey = manga.sourceInfo?.providerType || manga.sourceInfo?.sourceId || 'remote';
    const persistedPath = await LibraryCoverManager.persistCoverByFilesDir(
      filesDir,
      LibraryCoverType.MANGA,
      `${providerKey}_${manga.id}`,
      sourceCover
    );

    return persistedPath ? persistedPath : '';
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
      metadata: {
        authors: manga.metadata.authors ? manga.metadata.authors.concat() : [],
        artists: manga.metadata.artists ? manga.metadata.artists.concat() : [],
        genres: manga.metadata.genres ? manga.metadata.genres.concat() : [],
        themes: manga.metadata.themes ? manga.metadata.themes.concat() : [],
        demographics: manga.metadata.demographics ? manga.metadata.demographics.concat() : [],
        contentRating: manga.metadata.contentRating,
        publicationYear: manga.metadata.publicationYear,
        publisher: manga.metadata.publisher,
        serialization: manga.metadata.serialization
      },
      chapters: manga.chapters ? manga.chapters.concat() : [],
      readingProgress: {
        currentChapterId: manga.readingProgress.currentChapterId,
        currentPageIndex: manga.readingProgress.currentPageIndex,
        readingStatus: manga.readingProgress.readingStatus,
        totalReadingTime: manga.readingProgress.totalReadingTime,
        lastReadAt: manga.readingProgress.lastReadAt,
        readingPercentage: manga.readingProgress.readingPercentage
      },
      bookmarks: manga.bookmarks ? manga.bookmarks.concat() : [],
      readingSettings: {
        readingMode: manga.readingSettings.readingMode,
        readingDirection: manga.readingSettings.readingDirection,
        brightness: manga.readingSettings.brightness,
        keepScreenOn: manga.readingSettings.keepScreenOn,
        pageSpacing: manga.readingSettings.pageSpacing,
        showPageInfo: manga.readingSettings.showPageInfo,
        showPageIndicator: manga.readingSettings.showPageIndicator,
        fitMode: manga.readingSettings.fitMode,
        autoPageTurnInterval: manga.readingSettings.autoPageTurnInterval,
        skipIntroPages: manga.readingSettings.skipIntroPages,
        pageTurnAnimation: manga.readingSettings.pageTurnAnimation,
        doublePagePortraitLayout: manga.readingSettings.doublePagePortraitLayout,
        doublePageVerticalDirection: manga.readingSettings.doublePageVerticalDirection,
        filterSettings: {
          enabled: manga.readingSettings.filterSettings.enabled,
          brightness: manga.readingSettings.filterSettings.brightness,
          contrast: manga.readingSettings.filterSettings.contrast,
          saturation: manga.readingSettings.filterSettings.saturation,
          hue: manga.readingSettings.filterSettings.hue,
          gamma: manga.readingSettings.filterSettings.gamma,
          sepia: manga.readingSettings.filterSettings.sepia,
          invert: manga.readingSettings.filterSettings.invert,
          grayscale: manga.readingSettings.filterSettings.grayscale,
          blur: manga.readingSettings.filterSettings.blur
        },
        volumeKeyNavigation: manga.readingSettings.volumeKeyNavigation,
        curlBackOpacity: manga.readingSettings.curlBackOpacity,
        webtoonLeftMargin: manga.readingSettings.webtoonLeftMargin,
        webtoonRightMargin: manga.readingSettings.webtoonRightMargin,
        webtoonMarginSync: manga.readingSettings.webtoonMarginSync
      },
      isFavorite: manga.isFavorite,
      addedToLibraryAt: manga.addedToLibraryAt,
      lastUpdatedAt: manga.lastUpdatedAt,
      sourceInfo: manga.sourceInfo ? {
        sourceName: manga.sourceInfo.sourceName,
        sourceUrl: manga.sourceInfo.sourceUrl,
        sourceId: manga.sourceInfo.sourceId,
        externalId: manga.sourceInfo.externalId,
        sourceLanguage: manga.sourceInfo.sourceLanguage,
        requiresLogin: manga.sourceInfo.requiresLogin,
        apiVersion: manga.sourceInfo.apiVersion,
        isNSFW: manga.sourceInfo.isNSFW,
        providerType: manga.sourceInfo.providerType,
        providerItemId: manga.sourceInfo.providerItemId,
        providerInstanceId: manga.sourceInfo.providerInstanceId,
        providerContentType: manga.sourceInfo.providerContentType
      } : undefined,
      contentType: manga.contentType,
      isNSFW: manga.isNSFW,
      isPrivate: manga.isPrivate
    };
  }
}

export function getRemoteLibraryShelfManager(): RemoteLibraryShelfManager {
  return RemoteLibraryShelfManager.getInstance();
}
