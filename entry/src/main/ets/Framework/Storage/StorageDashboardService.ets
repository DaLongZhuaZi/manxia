import { SafeFileUtils } from '../../Utils/SafeFileUtils';
import { SafeUtils } from '../../Utils/SafeUtils';
import { storageStatistics } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { logger } from '../../Utils/Logger';
import { ImageCacheManager } from '../Cache/ImageCacheManager';
import { DiskCacheManager } from '../Cache/DiskCacheManager';
import { OnlineImageLoader } from '../Cache/OnlineImageLoader';
import { CachedContent, SourceContentCache } from '../Cache/SourceContentCache';
import { BookSourceCacheData, KomgaCacheData, SuwayomiCacheData, TabContentCacheManager } from '../Cache/TabContentCacheManager';
import { WebViewDataCacheManager } from '../Cache/WebViewDataCacheManager';
import { DatabaseManager } from '../Database/DatabaseManager';
import DownloadDirManager from './DownloadDirManager';

const TAG = 'StorageDashboardService';
const SOURCE_CONTENT_PREF_NAME = 'source_content_cache';
const SOURCE_CONTENT_PREF_KEY = 'cache_data';
const TAB_CONTENT_PREF_NAME = 'tab_content_cache';
const TAB_CONTENT_BOOK_SOURCE_KEY = 'book_source_cache';
const TAB_CONTENT_SUWAYOMI_KEY = 'suwayomi_cache';
const TAB_CONTENT_KOMGA_KEY = 'komga_cache';

export enum StorageSectionId {
  CLEANABLE = 'CLEANABLE',
  REMOTE_CACHE = 'REMOTE_CACHE',
  MEMORY = 'MEMORY',
  PROTECTED = 'PROTECTED'
}

export enum StorageBucketId {
  COVER_DISK_CACHE = 'COVER_DISK_CACHE',
  ONLINE_IMAGE_DISK_CACHE = 'ONLINE_IMAGE_DISK_CACHE',
  SANDBOX_CACHE_MISC = 'SANDBOX_CACHE_MISC',
  TEMP_IMAGE_CACHE = 'TEMP_IMAGE_CACHE',
  SYSTEM_RUNTIME_CACHE = 'SYSTEM_RUNTIME_CACHE',
  TEMP_FILES = 'TEMP_FILES',
  SOURCE_CONTENT_CACHE = 'SOURCE_CONTENT_CACHE',
  TAB_CONTENT_CACHE = 'TAB_CONTENT_CACHE',
  PERMANENT_MANGA_CACHE = 'PERMANENT_MANGA_CACHE',
  NOVEL_CHAPTER_CACHE = 'NOVEL_CHAPTER_CACHE',
  REMOTE_READ_ALOUD_CACHE = 'REMOTE_READ_ALOUD_CACHE',
  SUWAYOMI_COVERS = 'SUWAYOMI_COVERS',
  SUWAYOMI_SOURCE_ICONS = 'SUWAYOMI_SOURCE_ICONS',
  SUWAYOMI_CHAPTERS = 'SUWAYOMI_CHAPTERS',
  KOMGA_COVERS = 'KOMGA_COVERS',
  KOMGA_CHAPTERS = 'KOMGA_CHAPTERS',
  IMAGE_MEMORY_CACHE = 'IMAGE_MEMORY_CACHE',
  ONLINE_IMAGE_MEMORY_CACHE = 'ONLINE_IMAGE_MEMORY_CACHE',
  WEBVIEW_DATA_CACHE = 'WEBVIEW_DATA_CACHE',
  DATABASE = 'DATABASE',
  COMIC_FILES = 'COMIC_FILES',
  EBOOK_FILES = 'EBOOK_FILES',
  CHAPTER_FILES = 'CHAPTER_FILES',
  PLUGIN_FILES = 'PLUGIN_FILES',
  LIBRARY_COVERS = 'LIBRARY_COVERS',
  DOWNLOAD_MANGA = 'DOWNLOAD_MANGA'
}

export type StorageBucketPathKind = 'sandbox' | 'system' | 'download' | 'database' | 'preferences' | 'memory';
export type StorageBucketRisk = 'safe' | 'caution' | 'protected';

export interface StorageBucketSummary {
  id: StorageBucketId;
  section: StorageSectionId;
  title: string;
  subtitle: string;
  sizeBytes: number;
  itemCount: number;
  itemLabel: string;
  path: string;
  pathKind: StorageBucketPathKind;
  isClearable: boolean;
  risk: StorageBucketRisk;
  note: string;
  progressRatio: number;
  displayOrder: number;
}

export interface StorageSectionSummary {
  id: StorageSectionId;
  title: string;
  subtitle: string;
  totalSizeBytes: number;
  clearableSizeBytes: number;
  bucketCount: number;
}

export interface StorageOverviewSummary {
  bundleAppSizeBytes: number;
  bundleCacheSizeBytes: number;
  bundleDataSizeBytes: number;
  bundleTotalSizeBytes: number;
  deviceTotalSizeBytes: number;
  deviceFreeSizeBytes: number;
  scannedTotalSizeBytes: number;
  cleanableTotalSizeBytes: number;
  protectedTotalSizeBytes: number;
  memorySizeBytes: number;
  bucketCount: number;
  clearableBucketCount: number;
  updatedAt: number;
}

export interface StorageDashboardSnapshot {
  overview: StorageOverviewSummary;
  sections: StorageSectionSummary[];
  buckets: StorageBucketSummary[];
}

export interface StorageBucketClearResult {
  id: StorageBucketId;
  title: string;
  success: boolean;
  clearedSizeBytes: number;
  message: string;
}

export interface StorageClearResult {
  success: boolean;
  clearedSizeBytes: number;
  results: StorageBucketClearResult[];
  errors: string[];
}

interface DirectoryUsageStats {
  path: string;
  exists: boolean;
  sizeBytes: number;
  fileCount: number;
  latestModifiedAt: number;
}

interface StoragePathSet {
  filesDir: string;
  cacheDir: string;
  databaseDir: string;
  sandboxCacheDir: string;
  onlineImageDiskCacheDir: string;
  coverCacheDir: string;
  permanentCacheDir: string;
  tempImageCacheDir: string;
  tempFilesDir: string;
  comicFilesDir: string;
  ebookFilesDir: string;
  chapterFilesDir: string;
  pluginFilesDir: string;
  libraryCoversDir: string;
  novelCacheDir: string;
  remoteReadAloudDir: string;
  komgaRootDir: string;
  komgaCoverDir: string;
  komgaChapterDir: string;
  downloadBaseDir: string;
  downloadMangaDir: string;
  suwayomiCoverDir: string;
  suwayomiIconDir: string;
  suwayomiChapterDir: string;
}

interface PreferenceUsageStats {
  sizeBytes: number;
  entryCount: number;
  itemCount: number;
}

interface OptimisticOverviewDelta {
  bundleCacheFreedBytes: number;
  bundleDataFreedBytes: number;
  deviceFreedBytes: number;
}

interface BucketMetadata {
  section: StorageSectionId;
  title: string;
  subtitle: string;
  itemLabel: string;
  pathKind: StorageBucketPathKind;
  clearable: boolean;
  risk: StorageBucketRisk;
  note: string;
  displayOrder: number;
}

export class StorageDashboardService {
  private static instance: StorageDashboardService | null = null;
  private cachedSnapshot: StorageDashboardSnapshot | null = null;
  private cachedAt: number = 0;
  private readonly cacheWindowMs: number = 15000;
  private readonly databaseManager: DatabaseManager = DatabaseManager.getInstance();

  static getInstance(): StorageDashboardService {
    if (!StorageDashboardService.instance) {
      StorageDashboardService.instance = new StorageDashboardService();
    }
    return StorageDashboardService.instance;
  }

  async inspect(abilityContext: common.UIAbilityContext, forceRefresh: boolean = false): Promise<StorageDashboardSnapshot> {
    const now = Date.now();
    if (!forceRefresh && this.cachedSnapshot && (now - this.cachedAt) < this.cacheWindowMs) {
      return this.cachedSnapshot;
    }

    const paths = this.buildPathSet(abilityContext);
    const bundleStats = await this.loadBundleStats();
    const deviceTotalSizeBytes = await this.loadDeviceTotalSize();
    const deviceFreeSizeBytes = await this.loadDeviceFreeSize();

    const imageMemoryStats = await this.loadImageMemoryStats();
    const onlineMemoryStats = this.loadOnlineImageMemoryStats();
    const webViewMemoryStats = this.loadWebViewDataStats();
    const sourceContentStats = await this.loadSourceContentPreferenceStats(abilityContext);
    const tabContentStats = await this.loadTabContentPreferenceStats(abilityContext);

    const coverDiskUsage = this.scanDirectory(paths.coverCacheDir);
    const sandboxCacheRootUsage = this.scanDirectory(paths.sandboxCacheDir);
    const onlineImageDiskUsage = this.scanDirectory(paths.onlineImageDiskCacheDir);
    const sandboxCacheMiscUsage = this.subtractUsage(sandboxCacheRootUsage, onlineImageDiskUsage);
    const permanentCacheUsage = this.scanDirectory(paths.permanentCacheDir);
    const cacheDirUsage = this.scanDirectory(paths.cacheDir);
    const tempImageUsage = this.scanDirectory(paths.tempImageCacheDir);
    const systemRuntimeUsage = this.subtractUsage(cacheDirUsage, tempImageUsage);
    const tempFilesUsage = this.scanDirectory(paths.tempFilesDir);
    const novelCacheUsage = this.scanDirectory(paths.novelCacheDir);
    const remoteReadAloudUsage = this.scanDirectory(paths.remoteReadAloudDir);
    const suwayomiCoverUsage = this.scanDirectory(paths.suwayomiCoverDir);
    const suwayomiIconUsage = this.scanDirectory(paths.suwayomiIconDir);
    const suwayomiChapterUsage = this.scanDirectory(paths.suwayomiChapterDir);
    const komgaCoverUsage = this.scanDirectory(paths.komgaCoverDir);
    const komgaChapterUsage = this.scanDirectory(paths.komgaChapterDir);
    const databaseUsage = this.scanDirectory(paths.databaseDir);
    const comicFilesUsage = this.scanDirectory(paths.comicFilesDir);
    const ebookFilesUsage = this.scanDirectory(paths.ebookFilesDir);
    const chapterFilesUsage = this.scanDirectory(paths.chapterFilesDir);
    const pluginFilesUsage = this.scanDirectory(paths.pluginFilesDir);
    const libraryCoverUsage = this.scanDirectory(paths.libraryCoversDir);
    const downloadMangaUsage = this.scanDirectory(paths.downloadMangaDir);

    const buckets: StorageBucketSummary[] = [];
    buckets.push(this.buildDirectoryBucket(StorageBucketId.COVER_DISK_CACHE, coverDiskUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.ONLINE_IMAGE_DISK_CACHE, onlineImageDiskUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.SANDBOX_CACHE_MISC, sandboxCacheMiscUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.TEMP_IMAGE_CACHE, tempImageUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.SYSTEM_RUNTIME_CACHE, systemRuntimeUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.TEMP_FILES, tempFilesUsage));
    buckets.push(this.buildPreferenceBucket(StorageBucketId.SOURCE_CONTENT_CACHE, sourceContentStats));
    buckets.push(this.buildPreferenceBucket(StorageBucketId.TAB_CONTENT_CACHE, tabContentStats));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.PERMANENT_MANGA_CACHE, permanentCacheUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.NOVEL_CHAPTER_CACHE, novelCacheUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.REMOTE_READ_ALOUD_CACHE, remoteReadAloudUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.SUWAYOMI_COVERS, suwayomiCoverUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.SUWAYOMI_SOURCE_ICONS, suwayomiIconUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.SUWAYOMI_CHAPTERS, suwayomiChapterUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.KOMGA_COVERS, komgaCoverUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.KOMGA_CHAPTERS, komgaChapterUsage));
    buckets.push(this.buildMemoryBucket(StorageBucketId.IMAGE_MEMORY_CACHE, imageMemoryStats.sizeBytes, imageMemoryStats.fileCount, '张图片'));
    buckets.push(this.buildMemoryBucket(StorageBucketId.ONLINE_IMAGE_MEMORY_CACHE, onlineMemoryStats.sizeBytes, onlineMemoryStats.fileCount, '张图片'));
    buckets.push(this.buildMemoryBucket(StorageBucketId.WEBVIEW_DATA_CACHE, webViewMemoryStats.sizeBytes, webViewMemoryStats.fileCount, '条数据'));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.DATABASE, databaseUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.COMIC_FILES, comicFilesUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.EBOOK_FILES, ebookFilesUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.CHAPTER_FILES, chapterFilesUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.PLUGIN_FILES, pluginFilesUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.LIBRARY_COVERS, libraryCoverUsage));
    buckets.push(this.buildDirectoryBucket(StorageBucketId.DOWNLOAD_MANGA, downloadMangaUsage));

    buckets.sort((left: StorageBucketSummary, right: StorageBucketSummary) => {
      if (left.section !== right.section) {
        return this.getSectionOrder(left.section) - this.getSectionOrder(right.section);
      }
      if (left.displayOrder !== right.displayOrder) {
        return left.displayOrder - right.displayOrder;
      }
      return right.sizeBytes - left.sizeBytes;
    });

    const overview = this.buildOverview(bundleStats, deviceTotalSizeBytes, deviceFreeSizeBytes, buckets, now);
    const sections = this.buildSections(buckets);
    const snapshot: StorageDashboardSnapshot = {
      overview,
      sections,
      buckets
    };

    this.cachedSnapshot = snapshot;
    this.cachedAt = now;
    return snapshot;
  }

  async clearBuckets(
    abilityContext: common.UIAbilityContext,
    bucketIds: StorageBucketId[]
  ): Promise<StorageClearResult> {
    const snapshot = await this.inspect(abilityContext, true);
    const results: StorageBucketClearResult[] = [];
    const errors: string[] = [];
    let clearedSizeBytes = 0;
    const uniqueBucketIds = this.uniqueBucketIds(bucketIds);

    for (let index = 0; index < uniqueBucketIds.length; index++) {
      const bucketId = uniqueBucketIds[index];
      const bucket = this.findBucket(snapshot.buckets, bucketId);
      if (!bucket) {
        errors.push(`${bucketId}: 未找到存储项`);
        continue;
      }
      if (!bucket.isClearable) {
        const protectedResult: StorageBucketClearResult = {
          id: bucket.id,
          title: bucket.title,
          success: false,
          clearedSizeBytes: 0,
          message: '该项已受保护，不能直接清理'
        };
        results.push(protectedResult);
        errors.push(`${bucket.title}: 已受保护`);
        continue;
      }

      try {
        await this.clearSingleBucket(abilityContext, bucket.id);
        const successResult: StorageBucketClearResult = {
          id: bucket.id,
          title: bucket.title,
          success: true,
          clearedSizeBytes: bucket.sizeBytes,
          message: '清理完成'
        };
        results.push(successResult);
        clearedSizeBytes += bucket.sizeBytes;
      } catch (error) {
        const message = `${bucket.title}: ${String(error)}`;
        const failedResult: StorageBucketClearResult = {
          id: bucket.id,
          title: bucket.title,
          success: false,
          clearedSizeBytes: 0,
          message
        };
        results.push(failedResult);
        errors.push(message);
      }
    }

    this.cachedSnapshot = null;
    this.cachedAt = 0;

    const result: StorageClearResult = {
      success: errors.length <= 0,
      clearedSizeBytes,
      results,
      errors
    };
    return result;
  }

  createOptimisticSnapshot(
    snapshot: StorageDashboardSnapshot,
    clearedBucketIds: StorageBucketId[]
  ): StorageDashboardSnapshot {
    const affectedBucketIds = this.expandOptimisticBucketIds(clearedBucketIds);
    const nextBuckets: StorageBucketSummary[] = [];

    for (let index = 0; index < snapshot.buckets.length; index++) {
      const nextBucket = this.cloneBucket(snapshot.buckets[index]);
      if (this.containsBucketId(affectedBucketIds, nextBucket.id)) {
        nextBucket.sizeBytes = 0;
        nextBucket.itemCount = 0;
        nextBucket.progressRatio = 0;
      }
      nextBuckets.push(nextBucket);
    }

    const overviewDelta = this.buildOptimisticOverviewDelta(snapshot, clearedBucketIds);
    const bundleStats: storageStatistics.BundleStats = {
      appSize: snapshot.overview.bundleAppSizeBytes,
      cacheSize: Math.max(0, snapshot.overview.bundleCacheSizeBytes - overviewDelta.bundleCacheFreedBytes),
      dataSize: Math.max(0, snapshot.overview.bundleDataSizeBytes - overviewDelta.bundleDataFreedBytes)
    };
    const deviceFreeSizeBytes = Math.min(
      snapshot.overview.deviceTotalSizeBytes,
      snapshot.overview.deviceFreeSizeBytes + overviewDelta.deviceFreedBytes
    );
    const overview = this.buildOverview(
      bundleStats,
      snapshot.overview.deviceTotalSizeBytes,
      deviceFreeSizeBytes,
      nextBuckets,
      Date.now()
    );
    const sections = this.buildSections(nextBuckets);
    const optimisticSnapshot: StorageDashboardSnapshot = {
      overview,
      sections,
      buckets: nextBuckets
    };

    this.cachedSnapshot = optimisticSnapshot;
    this.cachedAt = optimisticSnapshot.overview.updatedAt;
    return optimisticSnapshot;
  }

  formatSize(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const base = 1024;
    const index = Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(base)));
    return `${(bytes / Math.pow(base, index)).toFixed(index === 0 ? 0 : 2)} ${units[index]}`;
  }

  private buildPathSet(abilityContext: common.UIAbilityContext): StoragePathSet {
    const filesDir = abilityContext.filesDir;
    const cacheDir = abilityContext.cacheDir;
    const databaseDir = abilityContext.databaseDir;
    const sandboxCacheDir = `${filesDir}/cache`;
    const downloadBaseDir = DownloadDirManager.isReady() ? DownloadDirManager.getPath() : '';
    const downloadMangaDir = downloadBaseDir.length > 0 ? `${downloadBaseDir}/manga` : '';
    const suwayomiRootDir = downloadBaseDir.length > 0 ? `${downloadBaseDir}/suwayomi` : '';
    const komgaRootDir = `${filesDir}/komga_cache`;
    const novelCacheDir = this.resolveNovelCacheDir(filesDir);

    return {
      filesDir,
      cacheDir,
      databaseDir,
      sandboxCacheDir,
      onlineImageDiskCacheDir: `${sandboxCacheDir}/image_cache`,
      coverCacheDir: `${filesDir}/covers`,
      permanentCacheDir: `${filesDir}/permanent_cache`,
      tempImageCacheDir: `${cacheDir}/temp_image_cache`,
      tempFilesDir: `${filesDir}/temp`,
      comicFilesDir: `${filesDir}/comics`,
      ebookFilesDir: `${filesDir}/ebooks`,
      chapterFilesDir: `${filesDir}/chapters`,
      pluginFilesDir: `${filesDir}/plugins`,
      libraryCoversDir: `${filesDir}/library_covers`,
      novelCacheDir,
      remoteReadAloudDir: `${filesDir}/read_aloud_remote`,
      komgaRootDir,
      komgaCoverDir: `${komgaRootDir}/covers`,
      komgaChapterDir: `${komgaRootDir}/chapters`,
      downloadBaseDir,
      downloadMangaDir,
      suwayomiCoverDir: suwayomiRootDir.length > 0 ? `${suwayomiRootDir}/covers` : '',
      suwayomiIconDir: suwayomiRootDir.length > 0 ? `${suwayomiRootDir}/source_icons` : '',
      suwayomiChapterDir: suwayomiRootDir.length > 0 ? `${suwayomiRootDir}/chapters` : ''
    };
  }

  private resolveNovelCacheDir(filesDir: string): string {
    try {
      const downloadSyncDirPath = AppStorage.get<string>('downloadSyncDirPath');
      if (downloadSyncDirPath && downloadSyncDirPath.length > 0) {
        return `${downloadSyncDirPath}/novel`;
      }
    } catch (_error) {
    }
    return `${filesDir}/novels`;
  }

  private async loadBundleStats(): Promise<storageStatistics.BundleStats> {
    try {
      return await storageStatistics.getCurrentBundleStats();
    } catch (error) {
      logger.warn(TAG, `读取应用存储统计失败: ${String(error)}`);
      const emptyStats: storageStatistics.BundleStats = {
        appSize: 0,
        cacheSize: 0,
        dataSize: 0
      };
      return emptyStats;
    }
  }

  private async loadDeviceTotalSize(): Promise<number> {
    try {
      return await storageStatistics.getTotalSize();
    } catch (error) {
      logger.debug(TAG, `读取设备总空间失败: ${String(error)}`);
      return 0;
    }
  }

  private async loadDeviceFreeSize(): Promise<number> {
    try {
      return await storageStatistics.getFreeSize();
    } catch (error) {
      logger.debug(TAG, `读取设备剩余空间失败: ${String(error)}`);
      return 0;
    }
  }

  private async loadImageMemoryStats(): Promise<DirectoryUsageStats> {
    try {
      const stats = await ImageCacheManager.getInstance().getCacheStats();
      return {
        path: '',
        exists: true,
        sizeBytes: stats.memoryCache.size,
        fileCount: stats.memoryCache.count,
        latestModifiedAt: 0
      };
    } catch (error) {
      logger.warn(TAG, `读取图片内存缓存统计失败: ${String(error)}`);
      return this.createEmptyUsage('');
    }
  }

  private loadOnlineImageMemoryStats(): DirectoryUsageStats {
    try {
      const stats = OnlineImageLoader.getInstance().getCacheStats();
      return {
        path: '',
        exists: true,
        sizeBytes: stats.size,
        fileCount: stats.count,
        latestModifiedAt: 0
      };
    } catch (error) {
      logger.warn(TAG, `读取在线图片内存缓存统计失败: ${String(error)}`);
      return this.createEmptyUsage('');
    }
  }

  private loadWebViewDataStats(): DirectoryUsageStats {
    try {
      const stats = WebViewDataCacheManager.getInstance().getStats();
      return {
        path: '',
        exists: true,
        sizeBytes: 0,
        fileCount: stats.totalCount,
        latestModifiedAt: 0
      };
    } catch (error) {
      logger.warn(TAG, `读取WebView缓存统计失败: ${String(error)}`);
      return this.createEmptyUsage('');
    }
  }

  private async loadSourceContentPreferenceStats(
    abilityContext: common.UIAbilityContext
  ): Promise<PreferenceUsageStats> {
    const cacheString = await this.readPreferenceString(abilityContext, SOURCE_CONTENT_PREF_NAME, SOURCE_CONTENT_PREF_KEY);
    if (cacheString.length <= 0) {
      return {
        sizeBytes: 0,
        entryCount: 0,
        itemCount: 0
      };
    }

    let entryCount = 0;
    let itemCount = 0;
    try {
      const parsed = SafeUtils.parseObj(cacheString) as Object;
      const entries = Object.entries(parsed) as [string, CachedContent][];
      entryCount = entries.length;
      for (let index = 0; index < entries.length; index++) {
        itemCount += entries[index][1].comics.length;
      }
    } catch (error) {
      logger.warn(TAG, `解析图源内容缓存失败: ${String(error)}`);
    }

    return {
      sizeBytes: this.measureStringBytes(cacheString),
      entryCount,
      itemCount
    };
  }

  private async loadTabContentPreferenceStats(
    abilityContext: common.UIAbilityContext
  ): Promise<PreferenceUsageStats> {
    const bookSourceCache = await this.readPreferenceString(abilityContext, TAB_CONTENT_PREF_NAME, TAB_CONTENT_BOOK_SOURCE_KEY);
    const suwayomiCache = await this.readPreferenceString(abilityContext, TAB_CONTENT_PREF_NAME, TAB_CONTENT_SUWAYOMI_KEY);
    const komgaCache = await this.readPreferenceString(abilityContext, TAB_CONTENT_PREF_NAME, TAB_CONTENT_KOMGA_KEY);

    let entryCount = 0;
    let itemCount = 0;

    if (bookSourceCache.length > 0) {
      entryCount += 1;
      itemCount += this.countBookSourceItems(bookSourceCache);
    }
    if (suwayomiCache.length > 0) {
      entryCount += 1;
      itemCount += this.countSuwayomiItems(suwayomiCache);
    }
    if (komgaCache.length > 0) {
      entryCount += 1;
      itemCount += this.countKomgaItems(komgaCache);
    }

    return {
      sizeBytes: this.measureStringBytes(bookSourceCache) + this.measureStringBytes(suwayomiCache) + this.measureStringBytes(komgaCache),
      entryCount,
      itemCount
    };
  }

  private countBookSourceItems(rawCache: string): number {
    try {
      const parsed = SafeUtils.parseObj(rawCache) as BookSourceCacheData;
      return parsed.bookSourceBooks.length;
    } catch (_error) {
      return 0;
    }
  }

  private countSuwayomiItems(rawCache: string): number {
    try {
      const parsed = SafeUtils.parseObj(rawCache) as SuwayomiCacheData;
      return parsed.mangas.length;
    } catch (_error) {
      return 0;
    }
  }

  private countKomgaItems(rawCache: string): number {
    try {
      const parsed = SafeUtils.parseObj(rawCache) as KomgaCacheData;
      return parsed.items.length;
    } catch (_error) {
      return 0;
    }
  }

  private async readPreferenceString(
    abilityContext: common.UIAbilityContext,
    prefName: string,
    key: string
  ): Promise<string> {
    try {
      const store = await preferences.getPreferences(abilityContext, prefName);
      const value = await store.get(key, '') as string;
      return value ? value : '';
    } catch (error) {
      logger.debug(TAG, `读取偏好缓存失败: ${prefName}/${key}, ${String(error)}`);
      return '';
    }
  }

  private measureStringBytes(value: string): number {
    if (!value || value.length <= 0) {
      return 0;
    }
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(value).byteLength;
  }

  private scanDirectory(path: string): DirectoryUsageStats {
    if (!path || path.length <= 0) {
      return this.createEmptyUsage(path);
    }
    if (!this.pathExists(path)) {
      return this.createEmptyUsage(path);
    }

    const stack: string[] = [path];
    let sizeBytes = 0;
    let fileCount = 0;
    let latestModifiedAt = 0;

    while (stack.length > 0) {
      const currentPath = stack.pop() as string;
      try {
        const stat = SafeFileUtils.statSync(currentPath);
        if (stat.isDirectory()) {
          const children = SafeFileUtils.listFileSync(currentPath);
          for (let index = 0; index < children.length; index++) {
            stack.push(`${currentPath}/${children[index]}`);
          }
        } else {
          sizeBytes += stat.size;
          fileCount += 1;
          if (stat.mtime > latestModifiedAt) {
            latestModifiedAt = stat.mtime;
          }
        }
      } catch (error) {
        logger.debug(TAG, `扫描目录节点失败: ${currentPath}, ${String(error)}`);
      }
    }

    return {
      path,
      exists: true,
      sizeBytes,
      fileCount,
      latestModifiedAt
    };
  }

  private subtractUsage(primary: DirectoryUsageStats, child: DirectoryUsageStats): DirectoryUsageStats {
    if (!primary.exists) {
      return this.createEmptyUsage(primary.path);
    }
    const usage: DirectoryUsageStats = {
      path: primary.path,
      exists: primary.exists,
      sizeBytes: Math.max(0, primary.sizeBytes - child.sizeBytes),
      fileCount: Math.max(0, primary.fileCount - child.fileCount),
      latestModifiedAt: primary.latestModifiedAt
    };
    return usage;
  }

  private createEmptyUsage(path: string): DirectoryUsageStats {
    return {
      path,
      exists: false,
      sizeBytes: 0,
      fileCount: 0,
      latestModifiedAt: 0
    };
  }

  private buildOverview(
    bundleStats: storageStatistics.BundleStats,
    deviceTotalSizeBytes: number,
    deviceFreeSizeBytes: number,
    buckets: StorageBucketSummary[],
    updatedAt: number
  ): StorageOverviewSummary {
    let scannedTotalSizeBytes = 0;
    let cleanableTotalSizeBytes = 0;
    let protectedTotalSizeBytes = 0;
    let memorySizeBytes = 0;
    let clearableBucketCount = 0;

    for (let index = 0; index < buckets.length; index++) {
      const bucket = buckets[index];
      if (bucket.section !== StorageSectionId.MEMORY) {
        scannedTotalSizeBytes += bucket.sizeBytes;
      } else {
        memorySizeBytes += bucket.sizeBytes;
      }
      if (bucket.isClearable) {
        cleanableTotalSizeBytes += bucket.sizeBytes;
        clearableBucketCount += 1;
      } else {
        protectedTotalSizeBytes += bucket.sizeBytes;
      }
    }

    const progressBase = scannedTotalSizeBytes > 0 ? scannedTotalSizeBytes : 1;
    for (let index = 0; index < buckets.length; index++) {
      const bucket = buckets[index];
      bucket.progressRatio = bucket.sizeBytes / progressBase;
    }

    return {
      bundleAppSizeBytes: bundleStats.appSize,
      bundleCacheSizeBytes: bundleStats.cacheSize,
      bundleDataSizeBytes: bundleStats.dataSize,
      bundleTotalSizeBytes: bundleStats.appSize + bundleStats.cacheSize + bundleStats.dataSize,
      deviceTotalSizeBytes,
      deviceFreeSizeBytes,
      scannedTotalSizeBytes,
      cleanableTotalSizeBytes,
      protectedTotalSizeBytes,
      memorySizeBytes,
      bucketCount: buckets.length,
      clearableBucketCount,
      updatedAt
    };
  }

  private cloneBucket(bucket: StorageBucketSummary): StorageBucketSummary {
    return {
      id: bucket.id,
      section: bucket.section,
      title: bucket.title,
      subtitle: bucket.subtitle,
      sizeBytes: bucket.sizeBytes,
      itemCount: bucket.itemCount,
      itemLabel: bucket.itemLabel,
      path: bucket.path,
      pathKind: bucket.pathKind,
      isClearable: bucket.isClearable,
      risk: bucket.risk,
      note: bucket.note,
      progressRatio: bucket.progressRatio,
      displayOrder: bucket.displayOrder
    };
  }

  private buildOptimisticOverviewDelta(
    snapshot: StorageDashboardSnapshot,
    clearedBucketIds: StorageBucketId[]
  ): OptimisticOverviewDelta {
    let bundleCacheFreedBytes = 0;
    let bundleDataFreedBytes = 0;
    let deviceFreedBytes = 0;

    const uniqueBucketIds = this.uniqueBucketIds(clearedBucketIds);
    for (let index = 0; index < uniqueBucketIds.length; index++) {
      const bucket = this.findBucket(snapshot.buckets, uniqueBucketIds[index]);
      if (!bucket || bucket.sizeBytes <= 0) {
        continue;
      }
      if (bucket.section !== StorageSectionId.MEMORY) {
        deviceFreedBytes += bucket.sizeBytes;
      }
      if (!this.shouldAffectBundleStorageOptimistically(bucket.id)) {
        continue;
      }
      if (this.isSystemCacheBucket(bucket.id)) {
        bundleCacheFreedBytes += bucket.sizeBytes;
      } else {
        bundleDataFreedBytes += bucket.sizeBytes;
      }
    }

    return {
      bundleCacheFreedBytes,
      bundleDataFreedBytes,
      deviceFreedBytes
    };
  }

  private expandOptimisticBucketIds(bucketIds: StorageBucketId[]): StorageBucketId[] {
    const affectedBucketIds = this.uniqueBucketIds(bucketIds);
    for (let index = 0; index < bucketIds.length; index++) {
      const bucketId = bucketIds[index];
      if (bucketId === StorageBucketId.COVER_DISK_CACHE &&
        !this.containsBucketId(affectedBucketIds, StorageBucketId.IMAGE_MEMORY_CACHE)) {
        affectedBucketIds.push(StorageBucketId.IMAGE_MEMORY_CACHE);
      }
    }
    return affectedBucketIds;
  }

  private shouldAffectBundleStorageOptimistically(bucketId: StorageBucketId): boolean {
    if (this.isDownloadBucket(bucketId)) {
      return false;
    }
    switch (bucketId) {
      case StorageBucketId.IMAGE_MEMORY_CACHE:
      case StorageBucketId.ONLINE_IMAGE_MEMORY_CACHE:
      case StorageBucketId.WEBVIEW_DATA_CACHE:
        return false;
      default:
        return true;
    }
  }

  private isSystemCacheBucket(bucketId: StorageBucketId): boolean {
    switch (bucketId) {
      case StorageBucketId.TEMP_IMAGE_CACHE:
      case StorageBucketId.SYSTEM_RUNTIME_CACHE:
        return true;
      default:
        return false;
    }
  }

  private isDownloadBucket(bucketId: StorageBucketId): boolean {
    switch (bucketId) {
      case StorageBucketId.NOVEL_CHAPTER_CACHE:
      case StorageBucketId.SUWAYOMI_COVERS:
      case StorageBucketId.SUWAYOMI_SOURCE_ICONS:
      case StorageBucketId.SUWAYOMI_CHAPTERS:
      case StorageBucketId.DOWNLOAD_MANGA:
        return true;
      default:
        return false;
    }
  }

  private buildDirectoryBucket(id: StorageBucketId, usage: DirectoryUsageStats): StorageBucketSummary {
    const metadata = this.getBucketMetadata(id);
    const bucket: StorageBucketSummary = {
      id,
      section: metadata.section,
      title: metadata.title,
      subtitle: metadata.subtitle,
      sizeBytes: usage.sizeBytes,
      itemCount: usage.fileCount,
      itemLabel: metadata.itemLabel,
      path: usage.path,
      pathKind: metadata.pathKind,
      isClearable: metadata.clearable,
      risk: metadata.risk,
      note: metadata.note,
      progressRatio: 0,
      displayOrder: metadata.displayOrder
    };
    if (usage.path.length <= 0 && id !== StorageBucketId.DOWNLOAD_MANGA) {
      bucket.note = metadata.note.length > 0 ? metadata.note : '路径未初始化';
    }
    if (usage.path.length <= 0 && id === StorageBucketId.DOWNLOAD_MANGA) {
      bucket.note = 'Download同步目录未连接';
    }
    return bucket;
  }

  private buildMemoryBucket(
    id: StorageBucketId,
    sizeBytes: number,
    itemCount: number,
    itemLabel: string
  ): StorageBucketSummary {
    const metadata = this.getBucketMetadata(id);
    return {
      id,
      section: metadata.section,
      title: metadata.title,
      subtitle: metadata.subtitle,
      sizeBytes,
      itemCount,
      itemLabel,
      path: '',
      pathKind: metadata.pathKind,
      isClearable: metadata.clearable,
      risk: metadata.risk,
      note: metadata.note,
      progressRatio: 0,
      displayOrder: metadata.displayOrder
    };
  }

  private buildPreferenceBucket(id: StorageBucketId, stats: PreferenceUsageStats): StorageBucketSummary {
    const metadata = this.getBucketMetadata(id);
    return {
      id,
      section: metadata.section,
      title: metadata.title,
      subtitle: metadata.subtitle,
      sizeBytes: stats.sizeBytes,
      itemCount: stats.itemCount > 0 ? stats.itemCount : stats.entryCount,
      itemLabel: metadata.itemLabel,
      path: metadata.pathKind === 'preferences' ? 'Preferences' : '',
      pathKind: metadata.pathKind,
      isClearable: metadata.clearable,
      risk: metadata.risk,
      note: metadata.note,
      progressRatio: 0,
      displayOrder: metadata.displayOrder
    };
  }

  private getBucketMetadata(id: StorageBucketId): BucketMetadata {
    switch (id) {
      case StorageBucketId.COVER_DISK_CACHE:
        return this.createBucketMetadata(StorageSectionId.CLEANABLE, '封面缓存', '书架、详情和图源封面缓存文件', '个文件', 'sandbox', true, 'safe', '会同步重置封面本地路径记录', 10);
      case StorageBucketId.ONLINE_IMAGE_DISK_CACHE:
        return this.createBucketMetadata(StorageSectionId.CLEANABLE, '在线图片磁盘缓存', 'filesDir/cache/image_cache 中的持久化页图缓存', '个文件', 'sandbox', true, 'safe', '', 20);
      case StorageBucketId.SANDBOX_CACHE_MISC:
        return this.createBucketMetadata(StorageSectionId.CLEANABLE, '沙箱其他缓存', 'filesDir/cache 下未单独归类的运行时缓存', '个文件', 'sandbox', true, 'safe', '', 30);
      case StorageBucketId.TEMP_IMAGE_CACHE:
        return this.createBucketMetadata(StorageSectionId.CLEANABLE, '临时章节图片缓存', 'downloadWhileReading 关闭时使用的临时图片缓存', '个文件', 'system', true, 'safe', '', 40);
      case StorageBucketId.SYSTEM_RUNTIME_CACHE:
        return this.createBucketMetadata(StorageSectionId.CLEANABLE, '系统运行缓存', 'cacheDir 下未单独归类的运行时缓存', '个文件', 'system', true, 'safe', '', 50);
      case StorageBucketId.TEMP_FILES:
        return this.createBucketMetadata(StorageSectionId.CLEANABLE, '临时文件', '处理中间产物与临时落地文件', '个文件', 'sandbox', true, 'safe', '', 60);
      case StorageBucketId.SOURCE_CONTENT_CACHE:
        return this.createBucketMetadata(StorageSectionId.CLEANABLE, '图源内容缓存', '热门、最新、搜索等结果页的持久化缓存', '项内容', 'preferences', true, 'safe', '按偏好存储估算大小', 70);
      case StorageBucketId.TAB_CONTENT_CACHE:
        return this.createBucketMetadata(StorageSectionId.CLEANABLE, '标签页持久缓存', '书源、Suwayomi、Komga Tab 的持久化快照', '项内容', 'preferences', true, 'safe', '按偏好存储估算大小', 80);
      case StorageBucketId.PERMANENT_MANGA_CACHE:
        return this.createBucketMetadata(StorageSectionId.REMOTE_CACHE, '永久章节图片缓存', '边看边下载与离线页图缓存', '个文件', 'sandbox', true, 'caution', '会清空在线漫画的本地图片缓存和下载状态', 10);
      case StorageBucketId.NOVEL_CHAPTER_CACHE:
        return this.createBucketMetadata(StorageSectionId.REMOTE_CACHE, '小说离线缓存', '章节正文、音频与章节列表缓存', '个文件', 'download', true, 'caution', '会影响小说离线阅读与听书', 20);
      case StorageBucketId.REMOTE_READ_ALOUD_CACHE:
        return this.createBucketMetadata(StorageSectionId.REMOTE_CACHE, '远程朗读音频缓存', '远程朗读分段音频与合并音频缓存', '个文件', 'sandbox', true, 'caution', '会清空远程听书缓存', 30);
      case StorageBucketId.SUWAYOMI_COVERS:
        return this.createBucketMetadata(StorageSectionId.REMOTE_CACHE, 'Suwayomi 封面缓存', 'Download 同步目录中的 Suwayomi 封面', '个文件', 'download', true, 'safe', '需要先连接 Download 同步目录', 40);
      case StorageBucketId.SUWAYOMI_SOURCE_ICONS:
        return this.createBucketMetadata(StorageSectionId.REMOTE_CACHE, 'Suwayomi 图标缓存', 'Download 同步目录中的 Suwayomi 图源图标', '个文件', 'download', true, 'safe', '需要先连接 Download 同步目录', 50);
      case StorageBucketId.SUWAYOMI_CHAPTERS:
        return this.createBucketMetadata(StorageSectionId.REMOTE_CACHE, 'Suwayomi 章节缓存', 'Download 同步目录中的 Suwayomi 章节图片', '个文件', 'download', true, 'caution', '会清空 Suwayomi 离线页图', 60);
      case StorageBucketId.KOMGA_COVERS:
        return this.createBucketMetadata(StorageSectionId.REMOTE_CACHE, 'Komga 封面缓存', 'Komga 浏览和详情页封面缓存', '个文件', 'sandbox', true, 'safe', '', 70);
      case StorageBucketId.KOMGA_CHAPTERS:
        return this.createBucketMetadata(StorageSectionId.REMOTE_CACHE, 'Komga 章节缓存', 'Komga 阅读页缓存的章节图片', '个文件', 'sandbox', true, 'caution', '会清空 Komga 离线页图', 80);
      case StorageBucketId.IMAGE_MEMORY_CACHE:
        return this.createBucketMetadata(StorageSectionId.MEMORY, '图片内存缓存', 'ImageCacheManager 当前持有的 PixelMap', '张图片', 'memory', true, 'safe', '仅在本次应用运行期间占用内存', 10);
      case StorageBucketId.ONLINE_IMAGE_MEMORY_CACHE:
        return this.createBucketMetadata(StorageSectionId.MEMORY, '在线图片内存缓存', 'OnlineImageLoader 的运行时缓存', '张图片', 'memory', true, 'safe', '仅在本次应用运行期间占用内存', 20);
      case StorageBucketId.WEBVIEW_DATA_CACHE:
        return this.createBucketMetadata(StorageSectionId.MEMORY, 'WebView 数据缓存', '漫画详情与章节列表的内存缓存', '条数据', 'memory', true, 'safe', '这是内存条目数，不单独落盘', 30);
      case StorageBucketId.DATABASE:
        return this.createBucketMetadata(StorageSectionId.PROTECTED, '应用数据库', '阅读记录、书架、图源与设置数据', '个文件', 'database', false, 'protected', '受保护数据，不在此页面直接清理', 10);
      case StorageBucketId.COMIC_FILES:
        return this.createBucketMetadata(StorageSectionId.PROTECTED, '本地漫画文件', '导入到沙箱中的本地漫画资源', '个文件', 'sandbox', false, 'protected', '受保护数据，不在此页面直接清理', 20);
      case StorageBucketId.EBOOK_FILES:
        return this.createBucketMetadata(StorageSectionId.PROTECTED, '电子书文件', '导入的电子书与离线资源', '个文件', 'sandbox', false, 'protected', '受保护数据，不在此页面直接清理', 30);
      case StorageBucketId.CHAPTER_FILES:
        return this.createBucketMetadata(StorageSectionId.PROTECTED, '章节文件', '已下载章节与离线正文文件', '个文件', 'sandbox', false, 'protected', '受保护数据，不在此页面直接清理', 40);
      case StorageBucketId.PLUGIN_FILES:
        return this.createBucketMetadata(StorageSectionId.PROTECTED, '插件与扩展文件', '图源插件、扩展与相关资源', '个文件', 'sandbox', false, 'protected', '受保护数据，不在此页面直接清理', 50);
      case StorageBucketId.LIBRARY_COVERS:
        return this.createBucketMetadata(StorageSectionId.PROTECTED, '书库持久封面', '书库条目的持久封面文件', '个文件', 'sandbox', false, 'protected', '受保护数据，不在此页面直接清理', 60);
      case StorageBucketId.DOWNLOAD_MANGA:
        return this.createBucketMetadata(StorageSectionId.PROTECTED, 'Download 同步漫画', 'Download 应用目录中的漫画输出与同步内容', '个文件', 'download', false, 'protected', '受保护数据，不在此页面直接清理', 70);
      default:
        return this.createBucketMetadata(StorageSectionId.PROTECTED, '未命名存储项', '未命名存储项', '个文件', 'sandbox', false, 'protected', '', 999);
    }
  }

  private createBucketMetadata(
    section: StorageSectionId,
    title: string,
    subtitle: string,
    itemLabel: string,
    pathKind: StorageBucketPathKind,
    clearable: boolean,
    risk: StorageBucketRisk,
    note: string,
    displayOrder: number
  ): BucketMetadata {
    return {
      section,
      title,
      subtitle,
      itemLabel,
      pathKind,
      clearable,
      risk,
      note,
      displayOrder
    };
  }

  private buildSections(buckets: StorageBucketSummary[]): StorageSectionSummary[] {
    const sections: StorageSectionSummary[] = [];
    sections.push(this.buildSection(StorageSectionId.CLEANABLE, buckets));
    sections.push(this.buildSection(StorageSectionId.REMOTE_CACHE, buckets));
    sections.push(this.buildSection(StorageSectionId.MEMORY, buckets));
    sections.push(this.buildSection(StorageSectionId.PROTECTED, buckets));
    return sections;
  }

  private buildSection(id: StorageSectionId, buckets: StorageBucketSummary[]): StorageSectionSummary {
    let totalSizeBytes = 0;
    let clearableSizeBytes = 0;
    let bucketCount = 0;
    for (let index = 0; index < buckets.length; index++) {
      const bucket = buckets[index];
      if (bucket.section !== id) {
        continue;
      }
      bucketCount += 1;
      totalSizeBytes += bucket.sizeBytes;
      if (bucket.isClearable) {
        clearableSizeBytes += bucket.sizeBytes;
      }
    }

    let title = '';
    let subtitle = '';
    switch (id) {
      case StorageSectionId.CLEANABLE:
        title = '可直接清理';
        subtitle = '应用可安全回收的临时缓存与持久化快照';
        break;
      case StorageSectionId.REMOTE_CACHE:
        title = '离线与远端缓存';
        subtitle = '会影响离线阅读、听书或远端浏览体验的缓存';
        break;
      case StorageSectionId.MEMORY:
        title = '运行时内存缓存';
        subtitle = '当前进程内的即时缓存，清理后不会删除本地文件';
        break;
      case StorageSectionId.PROTECTED:
        title = '受保护数据';
        subtitle = '本地资料与核心数据库，仅展示不在此页直接清理';
        break;
      default:
        title = '未分组';
        subtitle = '';
        break;
    }

    return {
      id,
      title,
      subtitle,
      totalSizeBytes,
      clearableSizeBytes,
      bucketCount
    };
  }

  private getSectionOrder(section: StorageSectionId): number {
    switch (section) {
      case StorageSectionId.CLEANABLE:
        return 0;
      case StorageSectionId.REMOTE_CACHE:
        return 1;
      case StorageSectionId.MEMORY:
        return 2;
      case StorageSectionId.PROTECTED:
        return 3;
      default:
        return 99;
    }
  }

  private findBucket(buckets: StorageBucketSummary[], bucketId: StorageBucketId): StorageBucketSummary | null {
    for (let index = 0; index < buckets.length; index++) {
      if (buckets[index].id === bucketId) {
        return buckets[index];
      }
    }
    return null;
  }

  private async clearSingleBucket(
    abilityContext: common.UIAbilityContext,
    bucketId: StorageBucketId
  ): Promise<void> {
    const paths = this.buildPathSet(abilityContext);

    switch (bucketId) {
      case StorageBucketId.COVER_DISK_CACHE:
        await ImageCacheManager.getInstance().clearAllCache();
        this.clearDirectoryContents(paths.coverCacheDir);
        await this.resetCoverCacheDatabaseState();
        break;
      case StorageBucketId.ONLINE_IMAGE_DISK_CACHE:
        await DiskCacheManager.getInstance().clear();
        this.clearDirectoryContents(paths.onlineImageDiskCacheDir);
        break;
      case StorageBucketId.SANDBOX_CACHE_MISC:
        this.clearDirectoryContents(paths.sandboxCacheDir, ['image_cache']);
        break;
      case StorageBucketId.TEMP_IMAGE_CACHE:
        this.clearDirectoryContents(paths.tempImageCacheDir);
        await this.resetOnlineImageCacheDatabaseState();
        break;
      case StorageBucketId.SYSTEM_RUNTIME_CACHE:
        this.clearDirectoryContents(paths.cacheDir, ['temp_image_cache']);
        break;
      case StorageBucketId.TEMP_FILES:
        this.clearDirectoryContents(paths.tempFilesDir);
        break;
      case StorageBucketId.SOURCE_CONTENT_CACHE:
        await SourceContentCache.getInstance().clearAll();
        break;
      case StorageBucketId.TAB_CONTENT_CACHE:
        await TabContentCacheManager.getInstance().clearAll();
        break;
      case StorageBucketId.PERMANENT_MANGA_CACHE:
        this.clearDirectoryContents(paths.permanentCacheDir);
        await this.resetOnlineImageCacheDatabaseState();
        break;
      case StorageBucketId.NOVEL_CHAPTER_CACHE:
        this.clearDirectoryContents(paths.novelCacheDir);
        break;
      case StorageBucketId.REMOTE_READ_ALOUD_CACHE:
        this.clearDirectoryContents(paths.remoteReadAloudDir);
        break;
      case StorageBucketId.SUWAYOMI_COVERS:
        this.clearDirectoryContents(paths.suwayomiCoverDir);
        break;
      case StorageBucketId.SUWAYOMI_SOURCE_ICONS:
        this.clearDirectoryContents(paths.suwayomiIconDir);
        break;
      case StorageBucketId.SUWAYOMI_CHAPTERS:
        this.clearDirectoryContents(paths.suwayomiChapterDir);
        break;
      case StorageBucketId.KOMGA_COVERS:
        this.clearDirectoryContents(paths.komgaCoverDir);
        break;
      case StorageBucketId.KOMGA_CHAPTERS:
        this.clearDirectoryContents(paths.komgaChapterDir);
        break;
      case StorageBucketId.IMAGE_MEMORY_CACHE:
        ImageCacheManager.getInstance().clearMemoryCache();
        break;
      case StorageBucketId.ONLINE_IMAGE_MEMORY_CACHE:
        OnlineImageLoader.getInstance().clearCache();
        break;
      case StorageBucketId.WEBVIEW_DATA_CACHE:
        WebViewDataCacheManager.getInstance().clearAll();
        break;
      default:
        throw new Error('UNSUPPORTED_CLEAR_OPERATION');
    }
  }

  private async resetCoverCacheDatabaseState(): Promise<void> {
    try {
      await this.databaseManager.executeSql(
        'UPDATE temp_manga_info SET localCoverPath = NULL WHERE localCoverPath IS NOT NULL',
        []
      );
    } catch (error) {
      logger.warn(TAG, `同步清理封面缓存记录失败: ${String(error)}`);
    }
  }

  private async resetOnlineImageCacheDatabaseState(): Promise<void> {
    try {
      await this.databaseManager.executeSql(
        'UPDATE online_page SET localPath = NULL, fileSize = 0, isDownloaded = 0 WHERE localPath IS NOT NULL OR isDownloaded = 1',
        []
      );
      await this.databaseManager.executeSql(
        'UPDATE online_chapter SET isDownloaded = 0, downloadPath = NULL WHERE isDownloaded = 1 OR downloadPath IS NOT NULL',
        []
      );
    } catch (error) {
      logger.warn(TAG, `同步清理在线图片缓存记录失败: ${String(error)}`);
    }
  }

  private clearDirectoryContents(path: string, excludedChildNames: string[] = []): void {
    if (!path || path.length <= 0 || !this.pathExists(path)) {
      return;
    }

    try {
      const children = SafeFileUtils.listFileSync(path);
      for (let index = 0; index < children.length; index++) {
        const childName = children[index];
        if (this.containsString(excludedChildNames, childName)) {
          continue;
        }
        const childPath = `${path}/${childName}`;
        this.deletePathRecursive(childPath);
      }
    } catch (error) {
      throw new Error(`清理目录失败: ${path}, ${String(error)}`);
    }
  }

  private deletePathRecursive(path: string): void {
    if (!path || path.length <= 0 || !this.pathExists(path)) {
      return;
    }

    const stat = SafeFileUtils.statSync(path);
    if (stat.isDirectory()) {
      const children = SafeFileUtils.listFileSync(path);
      for (let index = 0; index < children.length; index++) {
        this.deletePathRecursive(`${path}/${children[index]}`);
      }
      SafeFileUtils.rmdirSync(path);
      return;
    }

    SafeFileUtils.unlinkSync(path);
  }

  private pathExists(path: string): boolean {
    try {
      return SafeFileUtils.accessSync(path);
    } catch (_error) {
      return false;
    }
  }

  private containsString(values: string[], target: string): boolean {
    for (let index = 0; index < values.length; index++) {
      if (values[index] === target) {
        return true;
      }
    }
    return false;
  }

  private uniqueBucketIds(bucketIds: StorageBucketId[]): StorageBucketId[] {
    const uniqueIds: StorageBucketId[] = [];
    for (let index = 0; index < bucketIds.length; index++) {
      const bucketId = bucketIds[index];
      if (!this.containsBucketId(uniqueIds, bucketId)) {
        uniqueIds.push(bucketId);
      }
    }
    return uniqueIds;
  }

  private containsBucketId(bucketIds: StorageBucketId[], bucketId: StorageBucketId): boolean {
    for (let index = 0; index < bucketIds.length; index++) {
      if (bucketIds[index] === bucketId) {
        return true;
      }
    }
    return false;
  }
}
