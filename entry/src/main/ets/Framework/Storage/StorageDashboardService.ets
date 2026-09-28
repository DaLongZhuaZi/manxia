import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  ManagedStorageClearItemResult,
  ManagedStorageClearResult,
  ManagedStorageEntry,
  ManagedStorageGroup,
  ManagedStorageKind,
  ManagedStorageProviderStatus,
  ManagedStorageRisk,
  ManagedStorageSnapshot,
  UnifiedStorageCoordinator
} from './UnifiedStorageCoordinator';
import { StorageOperationRecord, StorageUsageMonitor, StorageUsageTrendPoint } from './StorageUsageMonitor';

const TAG = 'StorageDashboardService';

export enum StorageSectionId {
  SAFE_CACHE = 'SAFE_CACHE',
  TEMP_WORKSPACE = 'TEMP_WORKSPACE',
  OFFLINE_CACHE = 'OFFLINE_CACHE',
  RUNTIME_MEMORY = 'RUNTIME_MEMORY',
  USER_DATA = 'USER_DATA',
  BACKUP = 'BACKUP',
  EXTENSION = 'EXTENSION',
  LOGS = 'LOGS',
  DOWNLOAD_EXTERNAL = 'DOWNLOAD_EXTERNAL',
  PROTECTED = 'PROTECTED'
}

export enum StorageBucketId {
  COVER_DISK_CACHE = 'cover_disk_cache',
  ONLINE_IMAGE_DISK_CACHE = 'online_image_disk_cache',
  SANDBOX_CACHE_MISC = 'sandbox_cache_misc',
  TEMP_IMAGE_CACHE = 'temp_image_cache',
  SYSTEM_RUNTIME_CACHE = 'system_runtime_cache',
  TEMP_FILES = 'temp_files',
  SOURCE_CONTENT_CACHE = 'source_content_cache',
  TAB_CONTENT_CACHE = 'tab_content_cache',
  NETWORK_FOLDER_CACHE = 'network_folder_cache',
  ONLINE_DOWNLOAD_WORK = 'online_download_work',
  ONLINE_ARCHIVE_WORK = 'online_archive_work',
  ONLINE_CBZ_READER = 'online_cbz_reader',
  READER_IMAGE_ACTIONS = 'reader_image_actions',
  TRANSITION_SCREENSHOTS = 'transition_screenshots',
  PERMANENT_MANGA_CACHE = 'permanent_manga_cache',
  PRIVATE_ONLINE_ARCHIVE = 'private_online_archive',
  NOVEL_CHAPTER_CACHE = 'novel_chapter_cache',
  REMOTE_READ_ALOUD_CACHE = 'remote_read_aloud_cache',
  SUWAYOMI_COVERS = 'suwayomi_covers',
  SUWAYOMI_SOURCE_ICONS = 'suwayomi_source_icons',
  SUWAYOMI_CHAPTERS = 'suwayomi_chapters',
  KOMGA_COVERS = 'komga_covers',
  KOMGA_CHAPTERS = 'komga_chapters',
  IMAGE_MEMORY_CACHE = 'image_memory_cache',
  ONLINE_IMAGE_MEMORY_CACHE = 'online_image_memory_cache',
  WEBVIEW_DATA_CACHE = 'webview_data_cache',
  LOCAL_IMAGE_MEMORY_CACHE = 'local_image_memory_cache',
  DATABASE = 'database',
  COMIC_FILES = 'comic_files',
  EBOOK_FILES = 'ebook_files',
  CHAPTER_FILES = 'chapter_files',
  PLUGIN_FILES = 'plugin_files',
  LIBRARY_COVERS = 'library_covers',
  EBOOK_COVERS = 'ebook_covers',
  NOVEL_COVERS = 'novel_covers',
  BACKUP_FILES = 'backup_files',
  EXTENSION_REPOSITORY = 'extension_repository',
  CUSTOM_FONTS = 'custom_fonts',
  VERSION_HISTORY = 'version_history',
  ERROR_LOGS = 'error_logs',
  CRASH_LOGS = 'crash_logs',
  FEEDBACK_FILES = 'feedback_files',
  PRIVATE_DOWNLOADS = 'private_downloads',
  DOWNLOAD_MANGA = 'download_manga',
  UNMAPPED = 'unmapped'
}

export type StorageBucketPathKind = 'sandbox' | 'system' | 'download' | 'database' | 'preferences' | 'memory' | 'external';
export type StorageBucketRisk = 'safe' | 'caution' | 'danger' | 'protected';

export interface StorageBucketSummary {
  id: StorageBucketId;
  providerId: string;
  section: StorageSectionId;
  title: string;
  subtitle: string;
  sizeBytes: number;
  itemCount: number;
  itemLabel: string;
  path: string;
  pathKind: StorageBucketPathKind;
  isClearable: boolean;
  canDelete: boolean;
  autoClearEligible: boolean;
  risk: StorageBucketRisk;
  note: string;
  targetPage: string;
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
  dangerTotalSizeBytes: number;
  protectedTotalSizeBytes: number;
  memorySizeBytes: number;
  bucketCount: number;
  clearableBucketCount: number;
  failedProviderCount: number;
  updatedAt: number;
}

export interface StorageProviderStatusSummary {
  providerId: string;
  title: string;
  success: boolean;
  message: string;
  durationMs: number;
}

export interface StorageDashboardSnapshot {
  overview: StorageOverviewSummary;
  sections: StorageSectionSummary[];
  buckets: StorageBucketSummary[];
  providerStatuses: StorageProviderStatusSummary[];
  trend: StorageUsageTrendPoint[];
  operationRecords: StorageOperationRecord[];
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

class SectionMetadata {
  public title: string = '';
  public subtitle: string = '';
  public order: number = 0;
}

export class StorageDashboardService {
  private static instance: StorageDashboardService | null = null;
  private cachedSnapshot: StorageDashboardSnapshot | null = null;
  private cachedAt: number = 0;
  private readonly cacheWindowMs: number = 15000;
  private readonly coordinator: UnifiedStorageCoordinator = UnifiedStorageCoordinator.getInstance();
  private readonly monitor: StorageUsageMonitor = StorageUsageMonitor.getInstance();

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

    const managedSnapshot = await this.coordinator.inspect(abilityContext, forceRefresh);
    this.monitor.recordSnapshot(managedSnapshot);
    const snapshot = this.mapManagedSnapshot(managedSnapshot);
    this.cachedSnapshot = snapshot;
    this.cachedAt = managedSnapshot.overview.updatedAt;
    logger.debug(
      TAG,
      `统一存储快照: entries=${snapshot.buckets.length}, reclaimable=${snapshot.overview.cleanableTotalSizeBytes}, failedProviders=${snapshot.overview.failedProviderCount}`
    );
    return snapshot;
  }

  async clearBuckets(
    abilityContext: common.UIAbilityContext,
    bucketIds: StorageBucketId[]
  ): Promise<StorageClearResult> {
    const entryIds: string[] = [];
    const uniqueBucketIds = this.uniqueBucketIds(bucketIds);
    for (let index = 0; index < uniqueBucketIds.length; index++) {
      if (uniqueBucketIds[index] !== StorageBucketId.UNMAPPED) {
        entryIds.push(uniqueBucketIds[index]);
      }
    }

    const managedResult = await this.coordinator.clearEntries(abilityContext, entryIds, 'storage_dashboard');
    this.monitor.recordClearResult(managedResult);
    this.cachedSnapshot = null;
    this.cachedAt = 0;
    return this.mapClearResult(managedResult);
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

    const overview = this.rebuildOverviewFromBuckets(snapshot.overview, nextBuckets);
    const optimisticSnapshot: StorageDashboardSnapshot = {
      overview,
      sections: this.buildSections(nextBuckets),
      buckets: nextBuckets,
      providerStatuses: this.cloneProviderStatuses(snapshot.providerStatuses),
      trend: this.monitor.getHistory(),
      operationRecords: this.monitor.getOperationRecords()
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

  private mapManagedSnapshot(managedSnapshot: ManagedStorageSnapshot): StorageDashboardSnapshot {
    const buckets: StorageBucketSummary[] = [];
    for (let index = 0; index < managedSnapshot.entries.length; index++) {
      buckets.push(this.mapEntry(managedSnapshot.entries[index]));
    }
    this.updateProgressRatio(buckets);
    const snapshot: StorageDashboardSnapshot = {
      overview: this.mapOverview(managedSnapshot),
      sections: this.buildSections(buckets),
      buckets,
      providerStatuses: this.mapProviderStatuses(managedSnapshot.providerStatuses),
      trend: this.monitor.getHistory(),
      operationRecords: this.monitor.getOperationRecords()
    };
    return snapshot;
  }

  private mapEntry(entry: ManagedStorageEntry): StorageBucketSummary {
    const bucket: StorageBucketSummary = {
      id: this.toBucketId(entry.id),
      providerId: entry.providerId,
      section: this.mapGroup(entry.group),
      title: entry.title,
      subtitle: entry.subtitle,
      sizeBytes: entry.sizeBytes,
      itemCount: entry.itemCount,
      itemLabel: entry.itemLabel,
      path: entry.pathLabel.length > 0 ? entry.pathLabel : entry.path,
      pathKind: this.mapKind(entry.kind),
      isClearable: entry.canClear || entry.canDelete,
      canDelete: entry.canDelete,
      autoClearEligible: entry.autoClearEligible,
      risk: this.mapRisk(entry.risk),
      note: entry.note,
      targetPage: entry.targetPage,
      progressRatio: 0,
      displayOrder: entry.displayOrder
    };
    return bucket;
  }

  private mapOverview(managedSnapshot: ManagedStorageSnapshot): StorageOverviewSummary {
    const overview: StorageOverviewSummary = {
      bundleAppSizeBytes: managedSnapshot.overview.bundleAppSizeBytes,
      bundleCacheSizeBytes: managedSnapshot.overview.bundleCacheSizeBytes,
      bundleDataSizeBytes: managedSnapshot.overview.bundleDataSizeBytes,
      bundleTotalSizeBytes: managedSnapshot.overview.bundleTotalSizeBytes,
      deviceTotalSizeBytes: managedSnapshot.overview.deviceTotalSizeBytes,
      deviceFreeSizeBytes: managedSnapshot.overview.deviceFreeSizeBytes,
      scannedTotalSizeBytes: managedSnapshot.overview.scannedTotalSizeBytes,
      cleanableTotalSizeBytes: managedSnapshot.overview.reclaimableSizeBytes,
      dangerTotalSizeBytes: managedSnapshot.overview.dangerSizeBytes,
      protectedTotalSizeBytes: managedSnapshot.overview.protectedSizeBytes,
      memorySizeBytes: managedSnapshot.overview.memorySizeBytes,
      bucketCount: managedSnapshot.overview.entryCount,
      clearableBucketCount: managedSnapshot.overview.reclaimableEntryCount,
      failedProviderCount: managedSnapshot.overview.failedProviderCount,
      updatedAt: managedSnapshot.overview.updatedAt
    };
    return overview;
  }

  private mapProviderStatuses(statuses: ManagedStorageProviderStatus[]): StorageProviderStatusSummary[] {
    const result: StorageProviderStatusSummary[] = [];
    for (let index = 0; index < statuses.length; index++) {
      const status = statuses[index];
      const summary: StorageProviderStatusSummary = {
        providerId: status.providerId,
        title: status.title,
        success: status.success,
        message: status.message,
        durationMs: status.durationMs
      };
      result.push(summary);
    }
    return result;
  }

  private mapClearResult(result: ManagedStorageClearResult): StorageClearResult {
    const results: StorageBucketClearResult[] = [];
    for (let index = 0; index < result.results.length; index++) {
      results.push(this.mapClearItemResult(result.results[index]));
    }
    const mapped: StorageClearResult = {
      success: result.success,
      clearedSizeBytes: result.clearedSizeBytes,
      results,
      errors: this.cloneStrings(result.errors)
    };
    return mapped;
  }

  private mapClearItemResult(result: ManagedStorageClearItemResult): StorageBucketClearResult {
    const mapped: StorageBucketClearResult = {
      id: this.toBucketId(result.id),
      title: result.title,
      success: result.success,
      clearedSizeBytes: result.clearedSizeBytes,
      message: result.message
    };
    return mapped;
  }

  private rebuildOverviewFromBuckets(baseOverview: StorageOverviewSummary, buckets: StorageBucketSummary[]): StorageOverviewSummary {
    let scannedTotalSizeBytes = 0;
    let cleanableTotalSizeBytes = 0;
    let dangerTotalSizeBytes = 0;
    let protectedTotalSizeBytes = 0;
    let memorySizeBytes = 0;
    let clearableBucketCount = 0;

    for (let index = 0; index < buckets.length; index++) {
      const bucket = buckets[index];
      if (bucket.section === StorageSectionId.RUNTIME_MEMORY) {
        memorySizeBytes += bucket.sizeBytes;
      } else {
        scannedTotalSizeBytes += bucket.sizeBytes;
      }
      if (bucket.isClearable) {
        cleanableTotalSizeBytes += bucket.sizeBytes;
        clearableBucketCount += 1;
      }
      if (bucket.risk === 'danger') {
        dangerTotalSizeBytes += bucket.sizeBytes;
      }
      if (bucket.risk === 'protected') {
        protectedTotalSizeBytes += bucket.sizeBytes;
      }
    }

    this.updateProgressRatio(buckets);
    const overview: StorageOverviewSummary = {
      bundleAppSizeBytes: baseOverview.bundleAppSizeBytes,
      bundleCacheSizeBytes: baseOverview.bundleCacheSizeBytes,
      bundleDataSizeBytes: baseOverview.bundleDataSizeBytes,
      bundleTotalSizeBytes: baseOverview.bundleTotalSizeBytes,
      deviceTotalSizeBytes: baseOverview.deviceTotalSizeBytes,
      deviceFreeSizeBytes: baseOverview.deviceFreeSizeBytes,
      scannedTotalSizeBytes,
      cleanableTotalSizeBytes,
      dangerTotalSizeBytes,
      protectedTotalSizeBytes,
      memorySizeBytes,
      bucketCount: buckets.length,
      clearableBucketCount,
      failedProviderCount: baseOverview.failedProviderCount,
      updatedAt: Date.now()
    };
    return overview;
  }

  private updateProgressRatio(buckets: StorageBucketSummary[]): void {
    let scannedTotalSizeBytes = 0;
    for (let index = 0; index < buckets.length; index++) {
      if (buckets[index].section !== StorageSectionId.RUNTIME_MEMORY) {
        scannedTotalSizeBytes += buckets[index].sizeBytes;
      }
    }
    const progressBase = scannedTotalSizeBytes > 0 ? scannedTotalSizeBytes : 1;
    for (let index = 0; index < buckets.length; index++) {
      buckets[index].progressRatio = buckets[index].section === StorageSectionId.RUNTIME_MEMORY ? 0 : buckets[index].sizeBytes / progressBase;
    }
  }

  private buildSections(buckets: StorageBucketSummary[]): StorageSectionSummary[] {
    const sections: StorageSectionSummary[] = [];
    const orderedSections: StorageSectionId[] = [
      StorageSectionId.SAFE_CACHE,
      StorageSectionId.TEMP_WORKSPACE,
      StorageSectionId.OFFLINE_CACHE,
      StorageSectionId.RUNTIME_MEMORY,
      StorageSectionId.USER_DATA,
      StorageSectionId.BACKUP,
      StorageSectionId.EXTENSION,
      StorageSectionId.LOGS,
      StorageSectionId.DOWNLOAD_EXTERNAL,
      StorageSectionId.PROTECTED
    ];

    for (let index = 0; index < orderedSections.length; index++) {
      const section = this.buildSection(orderedSections[index], buckets);
      if (section.bucketCount > 0) {
        sections.push(section);
      }
    }
    return sections;
  }

  private buildSection(id: StorageSectionId, buckets: StorageBucketSummary[]): StorageSectionSummary {
    const metadata = this.getSectionMetadata(id);
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

    const section: StorageSectionSummary = {
      id,
      title: metadata.title,
      subtitle: metadata.subtitle,
      totalSizeBytes,
      clearableSizeBytes,
      bucketCount
    };
    return section;
  }

  private getSectionMetadata(sectionId: StorageSectionId): SectionMetadata {
    const metadata = new SectionMetadata();
    switch (sectionId) {
      case StorageSectionId.SAFE_CACHE:
        metadata.title = '缓存';
        metadata.subtitle = '安全缓存、偏好缓存和网络文件夹缓存，可直接回收';
        metadata.order = 0;
        break;
      case StorageSectionId.TEMP_WORKSPACE:
        metadata.title = '临时工作区';
        metadata.subtitle = '下载、归档、解压、截图等短期工作文件';
        metadata.order = 1;
        break;
      case StorageSectionId.OFFLINE_CACHE:
        metadata.title = '离线';
        metadata.subtitle = '漫画、小说、远程库等离线缓存，清理后需要重新拉取';
        metadata.order = 2;
        break;
      case StorageSectionId.RUNTIME_MEMORY:
        metadata.title = '运行时内存';
        metadata.subtitle = '当前进程持有的图片和 WebView 数据缓存';
        metadata.order = 3;
        break;
      case StorageSectionId.USER_DATA:
        metadata.title = '数据';
        metadata.subtitle = '导入文件、封面、字体和私有下载内容';
        metadata.order = 4;
        break;
      case StorageSectionId.BACKUP:
        metadata.title = '备份';
        metadata.subtitle = '备份与恢复页面生成或导入的备份文件';
        metadata.order = 5;
        break;
      case StorageSectionId.EXTENSION:
        metadata.title = '扩展';
        metadata.subtitle = '图源扩展仓库、插件和扩展运行资源';
        metadata.order = 6;
        break;
      case StorageSectionId.LOGS:
        metadata.title = '日志与诊断';
        metadata.subtitle = '错误、崩溃、反馈和版本历史缓存';
        metadata.order = 7;
        break;
      case StorageSectionId.DOWNLOAD_EXTERNAL:
        metadata.title = '外部 Download';
        metadata.subtitle = 'Download 同步目录中的外部内容，仅在授权后扫描';
        metadata.order = 8;
        break;
      case StorageSectionId.PROTECTED:
      default:
        metadata.title = '受保护数据';
        metadata.subtitle = '核心数据库和缺少一致性删除服务的数据，只展示和跳转';
        metadata.order = 9;
        break;
    }
    return metadata;
  }

  private mapGroup(group: ManagedStorageGroup): StorageSectionId {
    switch (group) {
      case ManagedStorageGroup.SAFE_CACHE:
        return StorageSectionId.SAFE_CACHE;
      case ManagedStorageGroup.TEMP_WORKSPACE:
        return StorageSectionId.TEMP_WORKSPACE;
      case ManagedStorageGroup.OFFLINE_CACHE:
        return StorageSectionId.OFFLINE_CACHE;
      case ManagedStorageGroup.RUNTIME_MEMORY:
        return StorageSectionId.RUNTIME_MEMORY;
      case ManagedStorageGroup.USER_DATA:
        return StorageSectionId.USER_DATA;
      case ManagedStorageGroup.BACKUP:
        return StorageSectionId.BACKUP;
      case ManagedStorageGroup.EXTENSION:
        return StorageSectionId.EXTENSION;
      case ManagedStorageGroup.LOGS:
        return StorageSectionId.LOGS;
      case ManagedStorageGroup.DOWNLOAD_EXTERNAL:
        return StorageSectionId.DOWNLOAD_EXTERNAL;
      case ManagedStorageGroup.PROTECTED:
      default:
        return StorageSectionId.PROTECTED;
    }
  }

  private mapKind(kind: ManagedStorageKind): StorageBucketPathKind {
    switch (kind) {
      case ManagedStorageKind.SYSTEM_CACHE:
        return 'system';
      case ManagedStorageKind.DOWNLOAD:
        return 'download';
      case ManagedStorageKind.DATABASE:
        return 'database';
      case ManagedStorageKind.PREFERENCES:
        return 'preferences';
      case ManagedStorageKind.MEMORY:
        return 'memory';
      case ManagedStorageKind.EXTERNAL:
        return 'external';
      case ManagedStorageKind.SANDBOX:
      default:
        return 'sandbox';
    }
  }

  private mapRisk(risk: ManagedStorageRisk): StorageBucketRisk {
    switch (risk) {
      case ManagedStorageRisk.CAUTION:
        return 'caution';
      case ManagedStorageRisk.DANGER:
        return 'danger';
      case ManagedStorageRisk.PROTECTED:
        return 'protected';
      case ManagedStorageRisk.SAFE:
      default:
        return 'safe';
    }
  }

  private toBucketId(id: string): StorageBucketId {
    switch (id) {
      case StorageBucketId.COVER_DISK_CACHE:
        return StorageBucketId.COVER_DISK_CACHE;
      case StorageBucketId.ONLINE_IMAGE_DISK_CACHE:
        return StorageBucketId.ONLINE_IMAGE_DISK_CACHE;
      case StorageBucketId.SANDBOX_CACHE_MISC:
        return StorageBucketId.SANDBOX_CACHE_MISC;
      case StorageBucketId.TEMP_IMAGE_CACHE:
        return StorageBucketId.TEMP_IMAGE_CACHE;
      case StorageBucketId.SYSTEM_RUNTIME_CACHE:
        return StorageBucketId.SYSTEM_RUNTIME_CACHE;
      case StorageBucketId.TEMP_FILES:
        return StorageBucketId.TEMP_FILES;
      case StorageBucketId.SOURCE_CONTENT_CACHE:
        return StorageBucketId.SOURCE_CONTENT_CACHE;
      case StorageBucketId.TAB_CONTENT_CACHE:
        return StorageBucketId.TAB_CONTENT_CACHE;
      case StorageBucketId.NETWORK_FOLDER_CACHE:
        return StorageBucketId.NETWORK_FOLDER_CACHE;
      case StorageBucketId.ONLINE_DOWNLOAD_WORK:
        return StorageBucketId.ONLINE_DOWNLOAD_WORK;
      case StorageBucketId.ONLINE_ARCHIVE_WORK:
        return StorageBucketId.ONLINE_ARCHIVE_WORK;
      case StorageBucketId.ONLINE_CBZ_READER:
        return StorageBucketId.ONLINE_CBZ_READER;
      case StorageBucketId.READER_IMAGE_ACTIONS:
        return StorageBucketId.READER_IMAGE_ACTIONS;
      case StorageBucketId.TRANSITION_SCREENSHOTS:
        return StorageBucketId.TRANSITION_SCREENSHOTS;
      case StorageBucketId.PERMANENT_MANGA_CACHE:
        return StorageBucketId.PERMANENT_MANGA_CACHE;
      case StorageBucketId.PRIVATE_ONLINE_ARCHIVE:
        return StorageBucketId.PRIVATE_ONLINE_ARCHIVE;
      case StorageBucketId.NOVEL_CHAPTER_CACHE:
        return StorageBucketId.NOVEL_CHAPTER_CACHE;
      case StorageBucketId.REMOTE_READ_ALOUD_CACHE:
        return StorageBucketId.REMOTE_READ_ALOUD_CACHE;
      case StorageBucketId.SUWAYOMI_COVERS:
        return StorageBucketId.SUWAYOMI_COVERS;
      case StorageBucketId.SUWAYOMI_SOURCE_ICONS:
        return StorageBucketId.SUWAYOMI_SOURCE_ICONS;
      case StorageBucketId.SUWAYOMI_CHAPTERS:
        return StorageBucketId.SUWAYOMI_CHAPTERS;
      case StorageBucketId.KOMGA_COVERS:
        return StorageBucketId.KOMGA_COVERS;
      case StorageBucketId.KOMGA_CHAPTERS:
        return StorageBucketId.KOMGA_CHAPTERS;
      case StorageBucketId.IMAGE_MEMORY_CACHE:
        return StorageBucketId.IMAGE_MEMORY_CACHE;
      case StorageBucketId.ONLINE_IMAGE_MEMORY_CACHE:
        return StorageBucketId.ONLINE_IMAGE_MEMORY_CACHE;
      case StorageBucketId.WEBVIEW_DATA_CACHE:
        return StorageBucketId.WEBVIEW_DATA_CACHE;
      case StorageBucketId.LOCAL_IMAGE_MEMORY_CACHE:
        return StorageBucketId.LOCAL_IMAGE_MEMORY_CACHE;
      case StorageBucketId.DATABASE:
        return StorageBucketId.DATABASE;
      case StorageBucketId.COMIC_FILES:
        return StorageBucketId.COMIC_FILES;
      case StorageBucketId.EBOOK_FILES:
        return StorageBucketId.EBOOK_FILES;
      case StorageBucketId.CHAPTER_FILES:
        return StorageBucketId.CHAPTER_FILES;
      case StorageBucketId.PLUGIN_FILES:
        return StorageBucketId.PLUGIN_FILES;
      case StorageBucketId.LIBRARY_COVERS:
        return StorageBucketId.LIBRARY_COVERS;
      case StorageBucketId.EBOOK_COVERS:
        return StorageBucketId.EBOOK_COVERS;
      case StorageBucketId.NOVEL_COVERS:
        return StorageBucketId.NOVEL_COVERS;
      case StorageBucketId.BACKUP_FILES:
        return StorageBucketId.BACKUP_FILES;
      case StorageBucketId.EXTENSION_REPOSITORY:
        return StorageBucketId.EXTENSION_REPOSITORY;
      case StorageBucketId.CUSTOM_FONTS:
        return StorageBucketId.CUSTOM_FONTS;
      case StorageBucketId.VERSION_HISTORY:
        return StorageBucketId.VERSION_HISTORY;
      case StorageBucketId.ERROR_LOGS:
        return StorageBucketId.ERROR_LOGS;
      case StorageBucketId.CRASH_LOGS:
        return StorageBucketId.CRASH_LOGS;
      case StorageBucketId.FEEDBACK_FILES:
        return StorageBucketId.FEEDBACK_FILES;
      case StorageBucketId.PRIVATE_DOWNLOADS:
        return StorageBucketId.PRIVATE_DOWNLOADS;
      case StorageBucketId.DOWNLOAD_MANGA:
        return StorageBucketId.DOWNLOAD_MANGA;
      default:
        return StorageBucketId.UNMAPPED;
    }
  }

  private cloneBucket(bucket: StorageBucketSummary): StorageBucketSummary {
    const clone: StorageBucketSummary = {
      id: bucket.id,
      providerId: bucket.providerId,
      section: bucket.section,
      title: bucket.title,
      subtitle: bucket.subtitle,
      sizeBytes: bucket.sizeBytes,
      itemCount: bucket.itemCount,
      itemLabel: bucket.itemLabel,
      path: bucket.path,
      pathKind: bucket.pathKind,
      isClearable: bucket.isClearable,
      canDelete: bucket.canDelete,
      autoClearEligible: bucket.autoClearEligible,
      risk: bucket.risk,
      note: bucket.note,
      targetPage: bucket.targetPage,
      progressRatio: bucket.progressRatio,
      displayOrder: bucket.displayOrder
    };
    return clone;
  }

  private cloneProviderStatuses(statuses: StorageProviderStatusSummary[]): StorageProviderStatusSummary[] {
    const result: StorageProviderStatusSummary[] = [];
    for (let index = 0; index < statuses.length; index++) {
      const status = statuses[index];
      const clone: StorageProviderStatusSummary = {
        providerId: status.providerId,
        title: status.title,
        success: status.success,
        message: status.message,
        durationMs: status.durationMs
      };
      result.push(clone);
    }
    return result;
  }

  private expandOptimisticBucketIds(bucketIds: StorageBucketId[]): StorageBucketId[] {
    const affectedBucketIds = this.uniqueBucketIds(bucketIds);
    for (let index = 0; index < bucketIds.length; index++) {
      const bucketId = bucketIds[index];
      if (bucketId === StorageBucketId.COVER_DISK_CACHE &&
        !this.containsBucketId(affectedBucketIds, StorageBucketId.IMAGE_MEMORY_CACHE)) {
        affectedBucketIds.push(StorageBucketId.IMAGE_MEMORY_CACHE);
      }
      if ((bucketId === StorageBucketId.TEMP_IMAGE_CACHE || bucketId === StorageBucketId.PERMANENT_MANGA_CACHE) &&
        !this.containsBucketId(affectedBucketIds, StorageBucketId.ONLINE_IMAGE_MEMORY_CACHE)) {
        affectedBucketIds.push(StorageBucketId.ONLINE_IMAGE_MEMORY_CACHE);
      }
    }
    return affectedBucketIds;
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

  private cloneStrings(values: string[]): string[] {
    const result: string[] = [];
    for (let index = 0; index < values.length; index++) {
      result.push(values[index]);
    }
    return result;
  }
}
