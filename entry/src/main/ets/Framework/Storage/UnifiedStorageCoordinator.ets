import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { storageStatistics } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { SafeFileUtils } from '../../Utils/SafeFileUtils';
import { SafeUtils } from '../../Utils/SafeUtils';
import { logger } from '../../Utils/Logger';
import { ImageCacheManager } from '../Cache/ImageCacheManager';
import { DiskCacheManager } from '../Cache/DiskCacheManager';
import { OnlineImageLoader } from '../Cache/OnlineImageLoader';
import { LocalImageCacheManager } from '../Cache/LocalImageCacheManager';
import { SourceContentCache, CachedContent } from '../Cache/SourceContentCache';
import { BookSourceCacheData, KomgaCacheData, SuwayomiCacheData, TabContentCacheManager } from '../Cache/TabContentCacheManager';
import { WebViewDataCacheManager } from '../Cache/WebViewDataCacheManager';
import { DatabaseManager } from '../Database/DatabaseManager';
import DownloadDirManager from './DownloadDirManager';
import { getNetworkFolderManager } from '../Network/NetworkFolderManager';
import { NetworkFolderCacheStats } from '../../Models/NetworkFolderModels';
import { CacheContentType, getCacheStatusService } from '../Services/CacheStatusService';

const TAG = 'UnifiedStorageCoordinator';
const SOURCE_CONTENT_PREF_NAME = 'source_content_cache';
const SOURCE_CONTENT_PREF_KEY = 'cache_data';
const TAB_CONTENT_PREF_NAME = 'tab_content_cache';
const TAB_CONTENT_BOOK_SOURCE_KEY = 'book_source_cache';
const TAB_CONTENT_SUWAYOMI_KEY = 'suwayomi_cache';
const TAB_CONTENT_KOMGA_KEY = 'komga_cache';

export enum ManagedStorageGroup {
  SAFE_CACHE = 'SAFE_CACHE',
  OFFLINE_CACHE = 'OFFLINE_CACHE',
  RUNTIME_MEMORY = 'RUNTIME_MEMORY',
  TEMP_WORKSPACE = 'TEMP_WORKSPACE',
  USER_DATA = 'USER_DATA',
  BACKUP = 'BACKUP',
  EXTENSION = 'EXTENSION',
  LOGS = 'LOGS',
  DOWNLOAD_EXTERNAL = 'DOWNLOAD_EXTERNAL',
  PROTECTED = 'PROTECTED'
}

export enum ManagedStorageKind {
  SANDBOX = 'SANDBOX',
  SYSTEM_CACHE = 'SYSTEM_CACHE',
  DOWNLOAD = 'DOWNLOAD',
  DATABASE = 'DATABASE',
  PREFERENCES = 'PREFERENCES',
  MEMORY = 'MEMORY',
  EXTERNAL = 'EXTERNAL'
}

export enum ManagedStorageRisk {
  SAFE = 'safe',
  CAUTION = 'caution',
  DANGER = 'danger',
  PROTECTED = 'protected'
}

export class ManagedStorageEntry {
  public id: string = '';
  public providerId: string = '';
  public title: string = '';
  public subtitle: string = '';
  public group: ManagedStorageGroup = ManagedStorageGroup.SAFE_CACHE;
  public kind: ManagedStorageKind = ManagedStorageKind.SANDBOX;
  public risk: ManagedStorageRisk = ManagedStorageRisk.SAFE;
  public sizeBytes: number = 0;
  public itemCount: number = 0;
  public itemLabel: string = '项';
  public path: string = '';
  public pathLabel: string = '';
  public canClear: boolean = false;
  public canDelete: boolean = false;
  public autoClearEligible: boolean = false;
  public targetPage: string = '';
  public note: string = '';
  public displayOrder: number = 0;
}

export class ManagedStorageOverview {
  public bundleAppSizeBytes: number = 0;
  public bundleCacheSizeBytes: number = 0;
  public bundleDataSizeBytes: number = 0;
  public bundleTotalSizeBytes: number = 0;
  public deviceTotalSizeBytes: number = 0;
  public deviceFreeSizeBytes: number = 0;
  public scannedTotalSizeBytes: number = 0;
  public reclaimableSizeBytes: number = 0;
  public dangerSizeBytes: number = 0;
  public protectedSizeBytes: number = 0;
  public memorySizeBytes: number = 0;
  public entryCount: number = 0;
  public reclaimableEntryCount: number = 0;
  public failedProviderCount: number = 0;
  public updatedAt: number = 0;
}

export class ManagedStorageProviderStatus {
  public providerId: string = '';
  public title: string = '';
  public success: boolean = true;
  public message: string = '';
  public durationMs: number = 0;
}

export class ManagedStorageSnapshot {
  public overview: ManagedStorageOverview = new ManagedStorageOverview();
  public entries: ManagedStorageEntry[] = [];
  public providerStatuses: ManagedStorageProviderStatus[] = [];
}

export class ManagedStorageClearRequest {
  public entryIds: string[] = [];
  public reason: string = '';
}

export class ManagedStorageClearItemResult {
  public id: string = '';
  public title: string = '';
  public providerId: string = '';
  public success: boolean = false;
  public clearedSizeBytes: number = 0;
  public message: string = '';
}

export class ManagedStorageClearResult {
  public success: boolean = false;
  public clearedSizeBytes: number = 0;
  public results: ManagedStorageClearItemResult[] = [];
  public errors: string[] = [];
}

export class ManagedContentCacheClearRequest {
  public contentType: CacheContentType = CacheContentType.MANGA;
  public contentId: string = '';
  public sourceId: number = 0;
  public title: string = '';
  public estimatedSizeBytes: number = 0;
}

export interface ManagedStorageProvider {
  providerId: string;
  title: string;
  inspect(abilityContext: common.UIAbilityContext): Promise<ManagedStorageEntry[]>;
  clear(abilityContext: common.UIAbilityContext, request: ManagedStorageClearRequest): Promise<ManagedStorageClearItemResult[]>;
}

class DirectoryUsageStats {
  public path: string = '';
  public exists: boolean = false;
  public sizeBytes: number = 0;
  public fileCount: number = 0;
  public latestModifiedAt: number = 0;
}

class PreferenceUsageStats {
  public sizeBytes: number = 0;
  public entryCount: number = 0;
  public itemCount: number = 0;
}

class ManagedStoragePathSet {
  public filesDir: string = '';
  public cacheDir: string = '';
  public databaseDir: string = '';
  public sandboxCacheDir: string = '';
  public onlineImageDiskCacheDir: string = '';
  public coverCacheDir: string = '';
  public permanentCacheDir: string = '';
  public tempImageCacheDir: string = '';
  public tempFilesDir: string = '';
  public comicFilesDir: string = '';
  public ebookFilesDir: string = '';
  public chapterFilesDir: string = '';
  public pluginFilesDir: string = '';
  public libraryCoversDir: string = '';
  public ebookCoversDir: string = '';
  public novelCoversDir: string = '';
  public novelCacheDir: string = '';
  public remoteReadAloudDir: string = '';
  public komgaRootDir: string = '';
  public komgaCoverDir: string = '';
  public komgaChapterDir: string = '';
  public downloadBaseDir: string = '';
  public downloadMangaDir: string = '';
  public suwayomiCoverDir: string = '';
  public suwayomiIconDir: string = '';
  public suwayomiChapterDir: string = '';
  public backupsDir: string = '';
  public extensionRepositoryDir: string = '';
  public customFontsDir: string = '';
  public versionHistoryDir: string = '';
  public errorLogsDir: string = '';
  public crashLogsDir: string = '';
  public feedbackDir: string = '';
  public privateDownloadsDir: string = '';
  public privateOnlineArchiveDir: string = '';
  public onlineDownloadWorkDir: string = '';
  public onlineArchiveWorkDir: string = '';
  public onlineCbzReaderDir: string = '';
  public readerImageActionsDir: string = '';
  public transitionScreenshotsDir: string = '';
}

class EntryDraft {
  public id: string = '';
  public providerId: string = '';
  public title: string = '';
  public subtitle: string = '';
  public group: ManagedStorageGroup = ManagedStorageGroup.SAFE_CACHE;
  public kind: ManagedStorageKind = ManagedStorageKind.SANDBOX;
  public risk: ManagedStorageRisk = ManagedStorageRisk.SAFE;
  public itemLabel: string = '个文件';
  public path: string = '';
  public pathLabel: string = '';
  public canClear: boolean = false;
  public canDelete: boolean = false;
  public autoClearEligible: boolean = false;
  public targetPage: string = '';
  public note: string = '';
  public displayOrder: number = 0;
}

abstract class BaseManagedStorageProvider implements ManagedStorageProvider {
  public providerId: string = '';
  public title: string = '';

  abstract inspect(abilityContext: common.UIAbilityContext): Promise<ManagedStorageEntry[]>;

  async clear(_abilityContext: common.UIAbilityContext, _request: ManagedStorageClearRequest): Promise<ManagedStorageClearItemResult[]> {
    const results: ManagedStorageClearItemResult[] = [];
    return results;
  }

  protected buildPathSet(abilityContext: common.UIAbilityContext): ManagedStoragePathSet {
    const paths = new ManagedStoragePathSet();
    paths.filesDir = abilityContext.filesDir;
    paths.cacheDir = abilityContext.cacheDir;
    paths.databaseDir = abilityContext.databaseDir;
    paths.sandboxCacheDir = `${paths.filesDir}/cache`;
    paths.onlineImageDiskCacheDir = `${paths.sandboxCacheDir}/image_cache`;
    paths.coverCacheDir = `${paths.filesDir}/covers`;
    paths.permanentCacheDir = `${paths.filesDir}/permanent_cache`;
    paths.tempImageCacheDir = `${paths.cacheDir}/temp_image_cache`;
    paths.tempFilesDir = `${paths.filesDir}/temp`;
    paths.comicFilesDir = `${paths.filesDir}/comics`;
    paths.ebookFilesDir = `${paths.filesDir}/ebooks`;
    paths.chapterFilesDir = `${paths.filesDir}/chapters`;
    paths.pluginFilesDir = `${paths.filesDir}/plugins`;
    paths.libraryCoversDir = `${paths.filesDir}/library_covers`;
    paths.ebookCoversDir = `${paths.filesDir}/ebook_covers`;
    paths.novelCoversDir = `${paths.filesDir}/novel_covers`;
    paths.novelCacheDir = this.resolveNovelCacheDir(paths.filesDir);
    paths.remoteReadAloudDir = `${paths.filesDir}/read_aloud_remote`;
    paths.komgaRootDir = `${paths.filesDir}/komga_cache`;
    paths.komgaCoverDir = `${paths.komgaRootDir}/covers`;
    paths.komgaChapterDir = `${paths.komgaRootDir}/chapters`;
    paths.downloadBaseDir = DownloadDirManager.isReady() ? DownloadDirManager.getPath() : '';
    paths.downloadMangaDir = paths.downloadBaseDir.length > 0 ? `${paths.downloadBaseDir}/manga` : '';
    const suwayomiRootDir = paths.downloadBaseDir.length > 0 ? `${paths.downloadBaseDir}/suwayomi` : '';
    paths.suwayomiCoverDir = suwayomiRootDir.length > 0 ? `${suwayomiRootDir}/covers` : '';
    paths.suwayomiIconDir = suwayomiRootDir.length > 0 ? `${suwayomiRootDir}/source_icons` : '';
    paths.suwayomiChapterDir = suwayomiRootDir.length > 0 ? `${suwayomiRootDir}/chapters` : '';
    paths.backupsDir = `${paths.filesDir}/backups`;
    paths.extensionRepositoryDir = `${paths.filesDir}/extensions-source`;
    paths.customFontsDir = `${paths.filesDir}/custom_fonts`;
    paths.versionHistoryDir = `${paths.filesDir}/version-history`;
    paths.errorLogsDir = `${paths.filesDir}/error_logs`;
    paths.crashLogsDir = `${paths.filesDir}/crash_logs`;
    paths.feedbackDir = `${paths.filesDir}/feedback`;
    paths.privateDownloadsDir = `${paths.filesDir}/downloads`;
    paths.privateOnlineArchiveDir = `${paths.privateDownloadsDir}/online_archive`;
    paths.onlineDownloadWorkDir = `${paths.cacheDir}/online_download_work`;
    paths.onlineArchiveWorkDir = `${paths.cacheDir}/online_archive_work`;
    paths.onlineCbzReaderDir = `${paths.cacheDir}/online_cbz_reader`;
    paths.readerImageActionsDir = `${paths.cacheDir}/reader_image_actions`;
    paths.transitionScreenshotsDir = `${paths.cacheDir}/transition_screenshots`;
    return paths;
  }

  protected resolveNovelCacheDir(filesDir: string): string {
    try {
      const downloadSyncDirPath = AppStorage.get<string>('downloadSyncDirPath');
      if (downloadSyncDirPath && downloadSyncDirPath.length > 0) {
        return `${downloadSyncDirPath}/novel`;
      }
    } catch (_error) {
    }
    return `${filesDir}/novels`;
  }

  protected createEmptyUsage(path: string): DirectoryUsageStats {
    const stats = new DirectoryUsageStats();
    stats.path = path;
    return stats;
  }

  protected pathExists(path: string): boolean {
    if (path.length <= 0) {
      return false;
    }
    try {
      return SafeFileUtils.accessSync(path);
    } catch (_error) {
      return false;
    }
  }

  protected scanDirectory(path: string): DirectoryUsageStats {
    if (path.length <= 0 || !this.pathExists(path)) {
      return this.createEmptyUsage(path);
    }

    const stack: string[] = [path];
    const stats = new DirectoryUsageStats();
    stats.path = path;
    stats.exists = true;

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
          stats.sizeBytes += stat.size;
          stats.fileCount += 1;
          if (stat.mtime > stats.latestModifiedAt) {
            stats.latestModifiedAt = stat.mtime;
          }
        }
      } catch (error) {
        logger.debug(TAG, `扫描目录节点失败: ${currentPath}, ${String(error)}`);
      }
    }

    return stats;
  }

  protected subtractUsages(primary: DirectoryUsageStats, children: DirectoryUsageStats[]): DirectoryUsageStats {
    if (!primary.exists) {
      return this.createEmptyUsage(primary.path);
    }
    const usage = new DirectoryUsageStats();
    usage.path = primary.path;
    usage.exists = primary.exists;
    usage.sizeBytes = primary.sizeBytes;
    usage.fileCount = primary.fileCount;
    usage.latestModifiedAt = primary.latestModifiedAt;
    for (let index = 0; index < children.length; index++) {
      usage.sizeBytes = Math.max(0, usage.sizeBytes - children[index].sizeBytes);
      usage.fileCount = Math.max(0, usage.fileCount - children[index].fileCount);
    }
    return usage;
  }

  protected buildEntry(draft: EntryDraft, usage: DirectoryUsageStats): ManagedStorageEntry {
    const entry = new ManagedStorageEntry();
    entry.id = draft.id;
    entry.providerId = draft.providerId.length > 0 ? draft.providerId : this.providerId;
    entry.title = draft.title;
    entry.subtitle = draft.subtitle;
    entry.group = draft.group;
    entry.kind = draft.kind;
    entry.risk = draft.risk;
    entry.sizeBytes = usage.sizeBytes;
    entry.itemCount = usage.fileCount;
    entry.itemLabel = draft.itemLabel;
    entry.path = usage.path.length > 0 ? usage.path : draft.path;
    entry.pathLabel = draft.pathLabel.length > 0 ? draft.pathLabel : entry.path;
    entry.canClear = draft.canClear;
    entry.canDelete = draft.canDelete;
    entry.autoClearEligible = draft.autoClearEligible;
    entry.targetPage = draft.targetPage;
    entry.note = draft.note;
    entry.displayOrder = draft.displayOrder;
    if (entry.path.length <= 0 && entry.kind === ManagedStorageKind.DOWNLOAD) {
      entry.note = entry.note.length > 0 ? entry.note : 'Download 同步目录未连接';
      entry.pathLabel = 'Download 同步目录未连接';
    }
    return entry;
  }

  protected createClearResult(entry: ManagedStorageEntry, success: boolean, clearedSizeBytes: number, message: string): ManagedStorageClearItemResult {
    const result = new ManagedStorageClearItemResult();
    result.id = entry.id;
    result.title = entry.title;
    result.providerId = entry.providerId;
    result.success = success;
    result.clearedSizeBytes = clearedSizeBytes;
    result.message = message;
    return result;
  }

  protected containsString(items: string[], value: string): boolean {
    for (let index = 0; index < items.length; index++) {
      if (items[index] === value) {
        return true;
      }
    }
    return false;
  }

  protected normalizePath(path: string): string {
    return path.replace(/\\/g, '/');
  }

  protected isPathUnderRoot(path: string, root: string): boolean {
    const normalizedPath = this.normalizePath(path);
    const normalizedRoot = this.normalizePath(root);
    if (normalizedPath === normalizedRoot) {
      return true;
    }
    return normalizedPath.startsWith(`${normalizedRoot}/`);
  }

  protected assertClearPathAllowed(path: string, roots: string[]): void {
    if (path.length <= 0) {
      throw new Error('清理路径为空');
    }
    for (let index = 0; index < roots.length; index++) {
      if (roots[index].length > 0 && this.isPathUnderRoot(path, roots[index])) {
        return;
      }
    }
    throw new Error(`清理路径不在允许范围内: ${path}`);
  }

  protected clearDirectoryContents(path: string, roots: string[], excludedChildNames: string[] = []): void {
    if (path.length <= 0 || !this.pathExists(path)) {
      return;
    }
    this.assertClearPathAllowed(path, roots);
    const children = SafeFileUtils.listFileSync(path);
    for (let index = 0; index < children.length; index++) {
      const childName = children[index];
      if (this.containsString(excludedChildNames, childName)) {
        continue;
      }
      this.deletePathRecursive(`${path}/${childName}`, roots);
    }
  }

  protected deletePathRecursive(path: string, roots: string[]): void {
    if (path.length <= 0 || !this.pathExists(path)) {
      return;
    }
    this.assertClearPathAllowed(path, roots);
    const stat = SafeFileUtils.statSync(path);
    if (stat.isDirectory()) {
      const children = SafeFileUtils.listFileSync(path);
      for (let index = 0; index < children.length; index++) {
        this.deletePathRecursive(`${path}/${children[index]}`, roots);
      }
      SafeFileUtils.rmdirSync(path);
      return;
    }
    SafeFileUtils.unlinkSync(path);
  }
}

class DefaultDirectoryStorageProvider extends BaseManagedStorageProvider {
  private readonly databaseManager: DatabaseManager = DatabaseManager.getInstance();

  public constructor() {
    super();
    this.providerId = 'default_directory';
    this.title = '沙箱与目录存储';
  }

  async inspect(abilityContext: common.UIAbilityContext): Promise<ManagedStorageEntry[]> {
    const paths = this.buildPathSet(abilityContext);
    const entries: ManagedStorageEntry[] = [];

    const sandboxCacheRootUsage = this.scanDirectory(paths.sandboxCacheDir);
    const onlineImageDiskUsage = this.scanDirectory(paths.onlineImageDiskCacheDir);
    const sandboxCacheMiscUsage = this.subtractUsages(sandboxCacheRootUsage, [onlineImageDiskUsage]);

    const cacheDirUsage = this.scanDirectory(paths.cacheDir);
    const tempImageUsage = this.scanDirectory(paths.tempImageCacheDir);
    const onlineDownloadWorkUsage = this.scanDirectory(paths.onlineDownloadWorkDir);
    const onlineArchiveWorkUsage = this.scanDirectory(paths.onlineArchiveWorkDir);
    const onlineCbzReaderUsage = this.scanDirectory(paths.onlineCbzReaderDir);
    const readerImageActionsUsage = this.scanDirectory(paths.readerImageActionsDir);
    const transitionScreenshotsUsage = this.scanDirectory(paths.transitionScreenshotsDir);
    const systemRuntimeUsage = this.subtractUsages(cacheDirUsage, [
      tempImageUsage,
      onlineDownloadWorkUsage,
      onlineArchiveWorkUsage,
      onlineCbzReaderUsage,
      readerImageActionsUsage,
      transitionScreenshotsUsage
    ]);

    entries.push(this.buildKnownEntry('cover_disk_cache', '封面缓存', '书架、详情和图源封面缓存文件', ManagedStorageGroup.SAFE_CACHE, ManagedStorageKind.SANDBOX, ManagedStorageRisk.SAFE, paths.coverCacheDir, this.scanDirectory(paths.coverCacheDir), true, false, true, '会同步重置封面本地路径记录', 10));
    entries.push(this.buildKnownEntry('online_image_disk_cache', '在线图片磁盘缓存', 'filesDir/cache/image_cache 中的持久化页图缓存', ManagedStorageGroup.SAFE_CACHE, ManagedStorageKind.SANDBOX, ManagedStorageRisk.SAFE, paths.onlineImageDiskCacheDir, onlineImageDiskUsage, true, false, true, '', 20));
    entries.push(this.buildKnownEntry('sandbox_cache_misc', '沙箱其他缓存', 'filesDir/cache 下未单独归类的运行时缓存', ManagedStorageGroup.SAFE_CACHE, ManagedStorageKind.SANDBOX, ManagedStorageRisk.SAFE, paths.sandboxCacheDir, sandboxCacheMiscUsage, true, false, true, '', 30));
    entries.push(this.buildKnownEntry('temp_image_cache', '临时章节图片缓存', 'downloadWhileReading 关闭时使用的临时图片缓存', ManagedStorageGroup.SAFE_CACHE, ManagedStorageKind.SYSTEM_CACHE, ManagedStorageRisk.SAFE, paths.tempImageCacheDir, tempImageUsage, true, false, true, '', 40));
    entries.push(this.buildKnownEntry('system_runtime_cache', '系统运行缓存', 'cacheDir 下未单独归类的运行时缓存', ManagedStorageGroup.SAFE_CACHE, ManagedStorageKind.SYSTEM_CACHE, ManagedStorageRisk.SAFE, paths.cacheDir, systemRuntimeUsage, true, false, true, '', 50));
    entries.push(this.buildKnownEntry('temp_files', '临时文件', '处理中间产物与临时落地文件', ManagedStorageGroup.TEMP_WORKSPACE, ManagedStorageKind.SANDBOX, ManagedStorageRisk.SAFE, paths.tempFilesDir, this.scanDirectory(paths.tempFilesDir), true, false, true, '', 10));
    entries.push(this.buildKnownEntry('online_download_work', '在线下载工作区', '在线漫画下载中的临时工作目录', ManagedStorageGroup.TEMP_WORKSPACE, ManagedStorageKind.SYSTEM_CACHE, ManagedStorageRisk.SAFE, paths.onlineDownloadWorkDir, onlineDownloadWorkUsage, true, false, true, '', 20));
    entries.push(this.buildKnownEntry('online_archive_work', '在线归档工作区', '在线章节归档生成过程中的临时目录', ManagedStorageGroup.TEMP_WORKSPACE, ManagedStorageKind.SYSTEM_CACHE, ManagedStorageRisk.SAFE, paths.onlineArchiveWorkDir, onlineArchiveWorkUsage, true, false, true, '', 30));
    entries.push(this.buildKnownEntry('online_cbz_reader', 'CBZ 阅读解压缓存', '在线 CBZ 阅读时解压出的图片缓存', ManagedStorageGroup.TEMP_WORKSPACE, ManagedStorageKind.SYSTEM_CACHE, ManagedStorageRisk.SAFE, paths.onlineCbzReaderDir, onlineCbzReaderUsage, true, false, true, '', 40));
    entries.push(this.buildKnownEntry('reader_image_actions', '阅读器图片操作缓存', '阅读器分享、保存、转换等操作的临时文件', ManagedStorageGroup.TEMP_WORKSPACE, ManagedStorageKind.SYSTEM_CACHE, ManagedStorageRisk.SAFE, paths.readerImageActionsDir, readerImageActionsUsage, true, false, true, '', 50));
    entries.push(this.buildKnownEntry('transition_screenshots', '转场截图缓存', '阅读器打开/关闭动效使用的临时截图', ManagedStorageGroup.TEMP_WORKSPACE, ManagedStorageKind.SYSTEM_CACHE, ManagedStorageRisk.SAFE, paths.transitionScreenshotsDir, transitionScreenshotsUsage, true, false, true, '', 60));

    entries.push(this.buildKnownEntry('permanent_manga_cache', '永久章节图片缓存', '边看边下载与离线页图缓存', ManagedStorageGroup.OFFLINE_CACHE, ManagedStorageKind.SANDBOX, ManagedStorageRisk.CAUTION, paths.permanentCacheDir, this.scanDirectory(paths.permanentCacheDir), true, false, false, '会清空在线漫画的本地图片缓存和下载状态', 10));
    entries.push(this.buildKnownEntry('private_online_archive', '在线漫画归档缓存', 'filesDir/downloads/online_archive 中的在线章节归档文件', ManagedStorageGroup.OFFLINE_CACHE, ManagedStorageKind.SANDBOX, ManagedStorageRisk.CAUTION, paths.privateOnlineArchiveDir, this.scanDirectory(paths.privateOnlineArchiveDir), false, false, false, '按作品清理请进入下载管理或详情页，避免归档状态不一致', 20));
    entries.push(this.buildKnownEntry('novel_chapter_cache', '小说离线缓存', '章节正文、音频与章节列表缓存', ManagedStorageGroup.OFFLINE_CACHE, ManagedStorageKind.DOWNLOAD, ManagedStorageRisk.CAUTION, paths.novelCacheDir, this.scanDirectory(paths.novelCacheDir), true, false, false, '会影响小说离线阅读与听书', 30));
    entries.push(this.buildKnownEntry('remote_read_aloud_cache', '远程朗读音频缓存', '远程朗读分段音频与合并音频缓存', ManagedStorageGroup.OFFLINE_CACHE, ManagedStorageKind.SANDBOX, ManagedStorageRisk.CAUTION, paths.remoteReadAloudDir, this.scanDirectory(paths.remoteReadAloudDir), true, false, false, '会清空远程听书缓存', 40));
    entries.push(this.buildKnownEntry('suwayomi_covers', 'Suwayomi 封面缓存', 'Download 同步目录中的 Suwayomi 封面', ManagedStorageGroup.OFFLINE_CACHE, ManagedStorageKind.DOWNLOAD, ManagedStorageRisk.SAFE, paths.suwayomiCoverDir, this.scanDirectory(paths.suwayomiCoverDir), true, false, false, '需要先连接 Download 同步目录', 50));
    entries.push(this.buildKnownEntry('suwayomi_source_icons', 'Suwayomi 图标缓存', 'Download 同步目录中的 Suwayomi 图源图标', ManagedStorageGroup.OFFLINE_CACHE, ManagedStorageKind.DOWNLOAD, ManagedStorageRisk.SAFE, paths.suwayomiIconDir, this.scanDirectory(paths.suwayomiIconDir), true, false, false, '需要先连接 Download 同步目录', 60));
    entries.push(this.buildKnownEntry('suwayomi_chapters', 'Suwayomi 章节缓存', 'Download 同步目录中的 Suwayomi 章节图片', ManagedStorageGroup.OFFLINE_CACHE, ManagedStorageKind.DOWNLOAD, ManagedStorageRisk.CAUTION, paths.suwayomiChapterDir, this.scanDirectory(paths.suwayomiChapterDir), true, false, false, '会清空 Suwayomi 离线页图', 70));
    entries.push(this.buildKnownEntry('komga_covers', 'Komga 封面缓存', 'Komga 浏览和详情页封面缓存', ManagedStorageGroup.OFFLINE_CACHE, ManagedStorageKind.SANDBOX, ManagedStorageRisk.SAFE, paths.komgaCoverDir, this.scanDirectory(paths.komgaCoverDir), true, false, false, '', 80));
    entries.push(this.buildKnownEntry('komga_chapters', 'Komga 章节缓存', 'Komga 阅读页缓存的章节图片', ManagedStorageGroup.OFFLINE_CACHE, ManagedStorageKind.SANDBOX, ManagedStorageRisk.CAUTION, paths.komgaChapterDir, this.scanDirectory(paths.komgaChapterDir), true, false, false, '会清空 Komga 离线页图', 90));

    entries.push(this.buildKnownEntry('database', '应用数据库', '阅读记录、书架、图源与设置数据', ManagedStorageGroup.PROTECTED, ManagedStorageKind.DATABASE, ManagedStorageRisk.PROTECTED, paths.databaseDir, this.scanDirectory(paths.databaseDir), false, false, false, '受保护数据，不在此页直接清理', 10));
    entries.push(this.buildKnownEntry('comic_files', '本地漫画文件', '导入到沙箱中的本地漫画资源', ManagedStorageGroup.USER_DATA, ManagedStorageKind.SANDBOX, ManagedStorageRisk.PROTECTED, paths.comicFilesDir, this.scanDirectory(paths.comicFilesDir), false, false, false, '需要通过书库或文件导入页处理', 20));
    entries.push(this.buildKnownEntry('ebook_files', '电子书文件', '导入的电子书与离线资源', ManagedStorageGroup.USER_DATA, ManagedStorageKind.SANDBOX, ManagedStorageRisk.PROTECTED, paths.ebookFilesDir, this.scanDirectory(paths.ebookFilesDir), false, false, false, '需要通过书库或文件导入页处理', 30));
    entries.push(this.buildKnownEntry('chapter_files', '章节文件', '已下载章节与离线正文文件', ManagedStorageGroup.USER_DATA, ManagedStorageKind.SANDBOX, ManagedStorageRisk.PROTECTED, paths.chapterFilesDir, this.scanDirectory(paths.chapterFilesDir), false, false, false, '需要通过对应内容详情页处理', 40));
    entries.push(this.buildKnownEntry('plugin_files', '插件文件', '插件包与运行资源', ManagedStorageGroup.EXTENSION, ManagedStorageKind.SANDBOX, ManagedStorageRisk.PROTECTED, paths.pluginFilesDir, this.scanDirectory(paths.pluginFilesDir), false, false, false, '插件文件不在总控中直接删除', 10));
    entries.push(this.buildKnownEntry('library_covers', '书库持久封面', '书库条目的持久封面文件', ManagedStorageGroup.USER_DATA, ManagedStorageKind.SANDBOX, ManagedStorageRisk.PROTECTED, paths.libraryCoversDir, this.scanDirectory(paths.libraryCoversDir), false, false, false, '持久封面与书库记录绑定，不直接清理', 50));
    entries.push(this.buildKnownEntry('ebook_covers', '电子书封面', '电子书详情与书架使用的封面文件', ManagedStorageGroup.USER_DATA, ManagedStorageKind.SANDBOX, ManagedStorageRisk.DANGER, paths.ebookCoversDir, this.scanDirectory(paths.ebookCoversDir), true, true, false, '清理后可能需要重新生成或重新选择封面', 60));
    entries.push(this.buildKnownEntry('novel_covers', '小说封面', '小说封面生成器与备份恢复使用的封面文件', ManagedStorageGroup.USER_DATA, ManagedStorageKind.SANDBOX, ManagedStorageRisk.DANGER, paths.novelCoversDir, this.scanDirectory(paths.novelCoversDir), true, true, false, '清理后可能需要重新生成或同步封面', 70));
    entries.push(this.buildKnownEntry('backup_files', '本地备份文件', '备份与恢复页面生成或导入的本地备份', ManagedStorageGroup.BACKUP, ManagedStorageKind.SANDBOX, ManagedStorageRisk.DANGER, paths.backupsDir, this.scanDirectory(paths.backupsDir), true, true, false, '删除后无法从本机恢复，请确认已有其它备份', 10));
    entries.push(this.buildKnownEntry('extension_repository', '图源扩展仓库', 'extensions-source 中的图源仓库、索引和图标', ManagedStorageGroup.EXTENSION, ManagedStorageKind.SANDBOX, ManagedStorageRisk.DANGER, paths.extensionRepositoryDir, this.scanDirectory(paths.extensionRepositoryDir), true, true, false, '清理后需要重新同步图源仓库', 20));
    entries.push(this.buildKnownEntry('custom_fonts', '自定义字体文件', '导入的自定义字体资源', ManagedStorageGroup.USER_DATA, ManagedStorageKind.SANDBOX, ManagedStorageRisk.PROTECTED, paths.customFontsDir, this.scanDirectory(paths.customFontsDir), false, false, false, '字体需要通过字体设置页删除以同步偏好设置', 80));
    entries.push(this.buildKnownEntry('version_history', '版本历史缓存', '版本历史页面缓存的提交记录', ManagedStorageGroup.LOGS, ManagedStorageKind.SANDBOX, ManagedStorageRisk.SAFE, paths.versionHistoryDir, this.scanDirectory(paths.versionHistoryDir), true, false, true, '', 10));
    entries.push(this.buildKnownEntry('error_logs', '错误日志', '捕获的错误日志文件', ManagedStorageGroup.LOGS, ManagedStorageKind.SANDBOX, ManagedStorageRisk.SAFE, paths.errorLogsDir, this.scanDirectory(paths.errorLogsDir), true, false, true, '', 20));
    entries.push(this.buildKnownEntry('crash_logs', '崩溃日志', '崩溃记录和诊断文件', ManagedStorageGroup.LOGS, ManagedStorageKind.SANDBOX, ManagedStorageRisk.SAFE, paths.crashLogsDir, this.scanDirectory(paths.crashLogsDir), true, false, true, '', 30));
    entries.push(this.buildKnownEntry('feedback_files', '反馈附件', '反馈页面保存的本地附件和草稿', ManagedStorageGroup.LOGS, ManagedStorageKind.SANDBOX, ManagedStorageRisk.CAUTION, paths.feedbackDir, this.scanDirectory(paths.feedbackDir), true, false, false, '清理后本地反馈附件不可恢复', 40));
    entries.push(this.buildKnownEntry('private_downloads', '私有下载目录', 'filesDir/downloads 下的下载与归档内容', ManagedStorageGroup.USER_DATA, ManagedStorageKind.SANDBOX, ManagedStorageRisk.PROTECTED, paths.privateDownloadsDir, this.scanDirectory(paths.privateDownloadsDir), false, false, false, '部分子目录已单独展示；剩余内容通过下载管理处理', 90));
    entries.push(this.buildKnownEntry('download_manga', 'Download 同步漫画', 'Download 应用目录中的漫画输出与同步内容', ManagedStorageGroup.DOWNLOAD_EXTERNAL, ManagedStorageKind.DOWNLOAD, ManagedStorageRisk.PROTECTED, paths.downloadMangaDir, this.scanDirectory(paths.downloadMangaDir), false, false, false, '受保护外部内容，不在此页直接清理', 10));

    return entries;
  }

  async clear(abilityContext: common.UIAbilityContext, request: ManagedStorageClearRequest): Promise<ManagedStorageClearItemResult[]> {
    const entries = await this.inspect(abilityContext);
    const results: ManagedStorageClearItemResult[] = [];
    const paths = this.buildPathSet(abilityContext);
    const roots: string[] = [paths.filesDir, paths.cacheDir, paths.downloadBaseDir];

    for (let index = 0; index < request.entryIds.length; index++) {
      const entry = this.findEntry(entries, request.entryIds[index]);
      if (!entry) {
        continue;
      }
      if (!entry.canClear && !entry.canDelete) {
        results.push(this.createClearResult(entry, false, 0, '该项没有开放直接清理'));
        continue;
      }

      try {
        await this.clearKnownEntry(entry, paths, roots);
        results.push(this.createClearResult(entry, true, entry.sizeBytes, '清理完成'));
      } catch (error) {
        results.push(this.createClearResult(entry, false, 0, String(error)));
      }
    }
    return results;
  }

  private buildKnownEntry(
    id: string,
    title: string,
    subtitle: string,
    group: ManagedStorageGroup,
    kind: ManagedStorageKind,
    risk: ManagedStorageRisk,
    path: string,
    usage: DirectoryUsageStats,
    canClear: boolean,
    canDelete: boolean,
    autoClearEligible: boolean,
    note: string,
    displayOrder: number
  ): ManagedStorageEntry {
    const draft = new EntryDraft();
    draft.id = id;
    draft.title = title;
    draft.subtitle = subtitle;
    draft.group = group;
    draft.kind = kind;
    draft.risk = risk;
    draft.path = path;
    draft.itemLabel = '个文件';
    draft.canClear = canClear;
    draft.canDelete = canDelete;
    draft.autoClearEligible = autoClearEligible;
    draft.note = note;
    draft.displayOrder = displayOrder;
    draft.targetPage = this.getTargetPageForEntry(id);
    return this.buildEntry(draft, usage);
  }

  private getTargetPageForEntry(id: string): string {
    switch (id) {
      case 'backup_files':
        return 'BackupPage';
      case 'comic_files':
      case 'ebook_files':
      case 'chapter_files':
        return 'DataManagementPage';
      case 'download_manga':
      case 'private_downloads':
      case 'private_online_archive':
        return 'DownloadManagerPage';
      case 'extension_repository':
        return 'SourceManagementPage';
      case 'custom_fonts':
        return 'GlobalSettingsPage';
      default:
        return '';
    }
  }

  private findEntry(entries: ManagedStorageEntry[], id: string): ManagedStorageEntry | null {
    for (let index = 0; index < entries.length; index++) {
      if (entries[index].id === id) {
        return entries[index];
      }
    }
    return null;
  }

  private async clearKnownEntry(entry: ManagedStorageEntry, paths: ManagedStoragePathSet, roots: string[]): Promise<void> {
    switch (entry.id) {
      case 'cover_disk_cache':
        await ImageCacheManager.getInstance().clearAllCache();
        this.clearDirectoryContents(paths.coverCacheDir, roots);
        await this.resetCoverCacheDatabaseState();
        break;
      case 'online_image_disk_cache':
        await DiskCacheManager.getInstance().clear();
        this.clearDirectoryContents(paths.onlineImageDiskCacheDir, roots);
        break;
      case 'sandbox_cache_misc':
        this.clearDirectoryContents(paths.sandboxCacheDir, roots, ['image_cache']);
        break;
      case 'temp_image_cache':
        this.clearDirectoryContents(paths.tempImageCacheDir, roots);
        await this.resetOnlineImageCacheDatabaseState();
        break;
      case 'system_runtime_cache':
        this.clearDirectoryContents(paths.cacheDir, roots, [
          'temp_image_cache',
          'online_download_work',
          'online_archive_work',
          'online_cbz_reader',
          'reader_image_actions',
          'transition_screenshots'
        ]);
        break;
      case 'temp_files':
        this.clearDirectoryContents(paths.tempFilesDir, roots);
        break;
      case 'online_download_work':
        this.clearDirectoryContents(paths.onlineDownloadWorkDir, roots);
        break;
      case 'online_archive_work':
        this.clearDirectoryContents(paths.onlineArchiveWorkDir, roots);
        break;
      case 'online_cbz_reader':
        this.clearDirectoryContents(paths.onlineCbzReaderDir, roots);
        break;
      case 'reader_image_actions':
        this.clearDirectoryContents(paths.readerImageActionsDir, roots);
        break;
      case 'transition_screenshots':
        this.clearDirectoryContents(paths.transitionScreenshotsDir, roots);
        break;
      case 'permanent_manga_cache':
        this.clearDirectoryContents(paths.permanentCacheDir, roots);
        await this.resetOnlineImageCacheDatabaseState();
        break;
      case 'novel_chapter_cache':
        this.clearDirectoryContents(paths.novelCacheDir, roots);
        break;
      case 'remote_read_aloud_cache':
        this.clearDirectoryContents(paths.remoteReadAloudDir, roots);
        break;
      case 'suwayomi_covers':
        this.clearDirectoryContents(paths.suwayomiCoverDir, roots);
        break;
      case 'suwayomi_source_icons':
        this.clearDirectoryContents(paths.suwayomiIconDir, roots);
        break;
      case 'suwayomi_chapters':
        this.clearDirectoryContents(paths.suwayomiChapterDir, roots);
        break;
      case 'komga_covers':
        this.clearDirectoryContents(paths.komgaCoverDir, roots);
        break;
      case 'komga_chapters':
        this.clearDirectoryContents(paths.komgaChapterDir, roots);
        break;
      case 'ebook_covers':
        this.clearDirectoryContents(paths.ebookCoversDir, roots);
        break;
      case 'novel_covers':
        this.clearDirectoryContents(paths.novelCoversDir, roots);
        break;
      case 'backup_files':
        this.clearDirectoryContents(paths.backupsDir, roots);
        break;
      case 'extension_repository':
        this.clearDirectoryContents(paths.extensionRepositoryDir, roots);
        break;
      case 'version_history':
        this.clearDirectoryContents(paths.versionHistoryDir, roots);
        break;
      case 'error_logs':
        this.clearDirectoryContents(paths.errorLogsDir, roots);
        break;
      case 'crash_logs':
        this.clearDirectoryContents(paths.crashLogsDir, roots);
        break;
      case 'feedback_files':
        this.clearDirectoryContents(paths.feedbackDir, roots);
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
      await this.databaseManager.executeSql(
        'DELETE FROM online_chapter_cache_state',
        []
      );
    } catch (error) {
      logger.warn(TAG, `同步清理在线图片缓存记录失败: ${String(error)}`);
    }
  }
}

class PreferenceManagedStorageProvider extends BaseManagedStorageProvider {
  public constructor() {
    super();
    this.providerId = 'preferences_cache';
    this.title = '偏好缓存';
  }

  async inspect(abilityContext: common.UIAbilityContext): Promise<ManagedStorageEntry[]> {
    const entries: ManagedStorageEntry[] = [];
    const sourceStats = await this.loadSourceContentPreferenceStats(abilityContext);
    const tabStats = await this.loadTabContentPreferenceStats(abilityContext);
    entries.push(this.buildPreferenceEntry('source_content_cache', '图源内容缓存', '热门、最新、搜索等结果页的持久化缓存', sourceStats, 70));
    entries.push(this.buildPreferenceEntry('tab_content_cache', '标签页持久缓存', '书源、Suwayomi、Komga Tab 的持久化快照', tabStats, 80));
    return entries;
  }

  async clear(_abilityContext: common.UIAbilityContext, request: ManagedStorageClearRequest): Promise<ManagedStorageClearItemResult[]> {
    const entries = await this.inspect(_abilityContext);
    const results: ManagedStorageClearItemResult[] = [];
    for (let index = 0; index < request.entryIds.length; index++) {
      const entry = this.findEntry(entries, request.entryIds[index]);
      if (!entry) {
        continue;
      }
      try {
        if (entry.id === 'source_content_cache') {
          await SourceContentCache.getInstance().clearAll();
        } else if (entry.id === 'tab_content_cache') {
          await TabContentCacheManager.getInstance().clearAll();
        } else {
          throw new Error('UNSUPPORTED_CLEAR_OPERATION');
        }
        results.push(this.createClearResult(entry, true, entry.sizeBytes, '清理完成'));
      } catch (error) {
        results.push(this.createClearResult(entry, false, 0, String(error)));
      }
    }
    return results;
  }

  private findEntry(entries: ManagedStorageEntry[], id: string): ManagedStorageEntry | null {
    for (let index = 0; index < entries.length; index++) {
      if (entries[index].id === id) {
        return entries[index];
      }
    }
    return null;
  }

  private buildPreferenceEntry(id: string, title: string, subtitle: string, stats: PreferenceUsageStats, order: number): ManagedStorageEntry {
    const usage = new DirectoryUsageStats();
    usage.path = 'Preferences';
    usage.exists = true;
    usage.sizeBytes = stats.sizeBytes;
    usage.fileCount = stats.itemCount > 0 ? stats.itemCount : stats.entryCount;
    const draft = new EntryDraft();
    draft.id = id;
    draft.title = title;
    draft.subtitle = subtitle;
    draft.group = ManagedStorageGroup.SAFE_CACHE;
    draft.kind = ManagedStorageKind.PREFERENCES;
    draft.risk = ManagedStorageRisk.SAFE;
    draft.itemLabel = '项内容';
    draft.canClear = true;
    draft.autoClearEligible = true;
    draft.note = '按偏好存储估算大小';
    draft.displayOrder = order;
    return this.buildEntry(draft, usage);
  }

  private async loadSourceContentPreferenceStats(abilityContext: common.UIAbilityContext): Promise<PreferenceUsageStats> {
    const cacheString = await this.readPreferenceString(abilityContext, SOURCE_CONTENT_PREF_NAME, SOURCE_CONTENT_PREF_KEY);
    const stats = new PreferenceUsageStats();
    stats.sizeBytes = this.measureStringBytes(cacheString);
    if (cacheString.length <= 0) {
      return stats;
    }

    try {
      const parsed = SafeUtils.parseObj(cacheString) as Object;
      const entries = Object.entries(parsed) as [string, CachedContent][];
      stats.entryCount = entries.length;
      for (let index = 0; index < entries.length; index++) {
        stats.itemCount += entries[index][1].comics.length;
      }
    } catch (error) {
      logger.warn(TAG, `解析图源内容缓存失败: ${String(error)}`);
    }
    return stats;
  }

  private async loadTabContentPreferenceStats(abilityContext: common.UIAbilityContext): Promise<PreferenceUsageStats> {
    const bookSourceCache = await this.readPreferenceString(abilityContext, TAB_CONTENT_PREF_NAME, TAB_CONTENT_BOOK_SOURCE_KEY);
    const suwayomiCache = await this.readPreferenceString(abilityContext, TAB_CONTENT_PREF_NAME, TAB_CONTENT_SUWAYOMI_KEY);
    const komgaCache = await this.readPreferenceString(abilityContext, TAB_CONTENT_PREF_NAME, TAB_CONTENT_KOMGA_KEY);
    const stats = new PreferenceUsageStats();
    stats.sizeBytes = this.measureStringBytes(bookSourceCache) + this.measureStringBytes(suwayomiCache) + this.measureStringBytes(komgaCache);
    if (bookSourceCache.length > 0) {
      stats.entryCount += 1;
      stats.itemCount += this.countBookSourceItems(bookSourceCache);
    }
    if (suwayomiCache.length > 0) {
      stats.entryCount += 1;
      stats.itemCount += this.countSuwayomiItems(suwayomiCache);
    }
    if (komgaCache.length > 0) {
      stats.entryCount += 1;
      stats.itemCount += this.countKomgaItems(komgaCache);
    }
    return stats;
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

  private async readPreferenceString(abilityContext: common.UIAbilityContext, prefName: string, key: string): Promise<string> {
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
    if (value.length <= 0) {
      return 0;
    }
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(value).byteLength;
  }
}

class RuntimeManagedStorageProvider extends BaseManagedStorageProvider {
  public constructor() {
    super();
    this.providerId = 'runtime_cache';
    this.title = '运行时缓存';
  }

  async inspect(_abilityContext: common.UIAbilityContext): Promise<ManagedStorageEntry[]> {
    const entries: ManagedStorageEntry[] = [];
    entries.push(await this.buildImageMemoryEntry());
    entries.push(this.buildOnlineImageMemoryEntry());
    entries.push(this.buildWebViewDataEntry());
    entries.push(this.buildLocalImageMemoryEntry());
    return entries;
  }

  async clear(abilityContext: common.UIAbilityContext, request: ManagedStorageClearRequest): Promise<ManagedStorageClearItemResult[]> {
    const entries = await this.inspect(abilityContext);
    const results: ManagedStorageClearItemResult[] = [];
    for (let index = 0; index < request.entryIds.length; index++) {
      const entry = this.findEntry(entries, request.entryIds[index]);
      if (!entry) {
        continue;
      }
      try {
        if (entry.id === 'image_memory_cache') {
          ImageCacheManager.getInstance().clearMemoryCache();
        } else if (entry.id === 'online_image_memory_cache') {
          OnlineImageLoader.getInstance().clearCache();
        } else if (entry.id === 'webview_data_cache') {
          WebViewDataCacheManager.getInstance().clearAll();
        } else if (entry.id === 'local_image_memory_cache') {
          LocalImageCacheManager.getInstance().clear();
        } else {
          throw new Error('UNSUPPORTED_CLEAR_OPERATION');
        }
        results.push(this.createClearResult(entry, true, entry.sizeBytes, '清理完成'));
      } catch (error) {
        results.push(this.createClearResult(entry, false, 0, String(error)));
      }
    }
    return results;
  }

  private findEntry(entries: ManagedStorageEntry[], id: string): ManagedStorageEntry | null {
    for (let index = 0; index < entries.length; index++) {
      if (entries[index].id === id) {
        return entries[index];
      }
    }
    return null;
  }

  private async buildImageMemoryEntry(): Promise<ManagedStorageEntry> {
    let sizeBytes = 0;
    let count = 0;
    try {
      const stats = await ImageCacheManager.getInstance().getCacheStats();
      sizeBytes = stats.memoryCache.size;
      count = stats.memoryCache.count;
    } catch (error) {
      logger.warn(TAG, `读取图片内存缓存失败: ${String(error)}`);
    }
    return this.buildMemoryEntry('image_memory_cache', '图片内存缓存', 'ImageCacheManager 当前持有的 PixelMap', sizeBytes, count, '仅在本次应用运行期间占用内存', 10);
  }

  private buildOnlineImageMemoryEntry(): ManagedStorageEntry {
    let sizeBytes = 0;
    let count = 0;
    try {
      const stats = OnlineImageLoader.getInstance().getCacheStats();
      sizeBytes = stats.size;
      count = stats.count;
    } catch (error) {
      logger.warn(TAG, `读取在线图片内存缓存失败: ${String(error)}`);
    }
    return this.buildMemoryEntry('online_image_memory_cache', '在线图片内存缓存', 'OnlineImageLoader 的运行时缓存', sizeBytes, count, '仅在本次应用运行期间占用内存', 20);
  }

  private buildWebViewDataEntry(): ManagedStorageEntry {
    let count = 0;
    try {
      const stats = WebViewDataCacheManager.getInstance().getStats();
      count = stats.totalCount;
    } catch (error) {
      logger.warn(TAG, `读取 WebView 数据缓存失败: ${String(error)}`);
    }
    return this.buildMemoryEntry('webview_data_cache', 'WebView 数据缓存', '漫画详情与章节列表的内存缓存', 0, count, '这是内存条目数，不单独落盘', 30);
  }

  private buildLocalImageMemoryEntry(): ManagedStorageEntry {
    let sizeBytes = 0;
    let count = 0;
    try {
      const stats = LocalImageCacheManager.getInstance().getStats();
      sizeBytes = stats.size;
      count = stats.count;
    } catch (error) {
      logger.warn(TAG, `读取本地漫画 LRU 缓存失败: ${String(error)}`);
    }
    return this.buildMemoryEntry('local_image_memory_cache', '本地漫画 LRU 缓存', 'LocalImageCacheManager 的本地漫画降采样 PixelMap', sizeBytes, count, '条漫快速滚动使用，清理后会按需重新解码', 40);
  }

  private buildMemoryEntry(id: string, title: string, subtitle: string, sizeBytes: number, itemCount: number, note: string, order: number): ManagedStorageEntry {
    const usage = new DirectoryUsageStats();
    usage.path = '内存缓存';
    usage.exists = true;
    usage.sizeBytes = sizeBytes;
    usage.fileCount = itemCount;
    const draft = new EntryDraft();
    draft.id = id;
    draft.title = title;
    draft.subtitle = subtitle;
    draft.group = ManagedStorageGroup.RUNTIME_MEMORY;
    draft.kind = ManagedStorageKind.MEMORY;
    draft.risk = ManagedStorageRisk.SAFE;
    draft.itemLabel = '项';
    draft.canClear = true;
    draft.autoClearEligible = true;
    draft.note = note;
    draft.displayOrder = order;
    return this.buildEntry(draft, usage);
  }
}

class NetworkFolderManagedStorageProvider extends BaseManagedStorageProvider {
  public constructor() {
    super();
    this.providerId = 'network_folder_cache';
    this.title = '网络文件夹缓存';
  }

  async inspect(abilityContext: common.UIAbilityContext): Promise<ManagedStorageEntry[]> {
    const entries: ManagedStorageEntry[] = [];
    try {
      const manager = getNetworkFolderManager();
      await manager.initialize(abilityContext);
      const stats: NetworkFolderCacheStats = manager.getCacheStats();
      const usage = new DirectoryUsageStats();
      usage.path = '网络文件夹缓存';
      usage.exists = true;
      usage.sizeBytes = stats.totalBytes;
      usage.fileCount = stats.fileCount + stats.directoryCount;
      const draft = new EntryDraft();
      draft.id = 'network_folder_cache';
      draft.title = '网络文件夹缓存';
      draft.subtitle = 'WebDAV、SMB、FTP 网络文件夹的目录快照与下载缓存';
      draft.group = ManagedStorageGroup.SAFE_CACHE;
      draft.kind = ManagedStorageKind.EXTERNAL;
      draft.risk = ManagedStorageRisk.SAFE;
      draft.itemLabel = '项';
      draft.canClear = true;
      draft.autoClearEligible = true;
      draft.targetPage = 'NetworkFolderPage';
      draft.note = `${stats.directoryCount} 个目录快照 · ${stats.fileCount} 个文件缓存`;
      draft.displayOrder = 90;
      entries.push(this.buildEntry(draft, usage));
    } catch (error) {
      logger.warn(TAG, `读取网络文件夹缓存失败: ${String(error)}`);
    }
    return entries;
  }

  async clear(abilityContext: common.UIAbilityContext, request: ManagedStorageClearRequest): Promise<ManagedStorageClearItemResult[]> {
    const entries = await this.inspect(abilityContext);
    const results: ManagedStorageClearItemResult[] = [];
    for (let index = 0; index < request.entryIds.length; index++) {
      if (request.entryIds[index] !== 'network_folder_cache') {
        continue;
      }
      const entry = entries.length > 0 ? entries[0] : this.createFallbackEntry();
      try {
        const manager = getNetworkFolderManager();
        await manager.initialize(abilityContext);
        await manager.clearAllCaches();
        results.push(this.createClearResult(entry, true, entry.sizeBytes, '清理完成'));
      } catch (error) {
        results.push(this.createClearResult(entry, false, 0, String(error)));
      }
    }
    return results;
  }

  private createFallbackEntry(): ManagedStorageEntry {
    const entry = new ManagedStorageEntry();
    entry.id = 'network_folder_cache';
    entry.providerId = this.providerId;
    entry.title = '网络文件夹缓存';
    entry.canClear = true;
    return entry;
  }
}

export class UnifiedStorageCoordinator {
  private static instance: UnifiedStorageCoordinator | null = null;
  private providers: ManagedStorageProvider[] = [];
  private cachedSnapshot: ManagedStorageSnapshot | null = null;
  private cachedAt: number = 0;
  private readonly cacheWindowMs: number = 15000;

  private constructor() {
    this.registerDefaultProviders();
  }

  static getInstance(): UnifiedStorageCoordinator {
    if (!UnifiedStorageCoordinator.instance) {
      UnifiedStorageCoordinator.instance = new UnifiedStorageCoordinator();
    }
    return UnifiedStorageCoordinator.instance;
  }

  registerProvider(provider: ManagedStorageProvider): void {
    for (let index = 0; index < this.providers.length; index++) {
      if (this.providers[index].providerId === provider.providerId) {
        this.providers[index] = provider;
        this.cachedSnapshot = null;
        this.cachedAt = 0;
        return;
      }
    }
    this.providers.push(provider);
    this.cachedSnapshot = null;
    this.cachedAt = 0;
  }

  async inspect(abilityContext: common.UIAbilityContext, forceRefresh: boolean = false): Promise<ManagedStorageSnapshot> {
    const now = Date.now();
    if (!forceRefresh && this.cachedSnapshot && (now - this.cachedAt) < this.cacheWindowMs) {
      return this.cachedSnapshot;
    }

    const snapshot = new ManagedStorageSnapshot();
    snapshot.overview = await this.loadOverviewBase(now);

    for (let index = 0; index < this.providers.length; index++) {
      const provider = this.providers[index];
      const startedAt = Date.now();
      const status = new ManagedStorageProviderStatus();
      status.providerId = provider.providerId;
      status.title = provider.title;
      try {
        const entries = await provider.inspect(abilityContext);
        for (let entryIndex = 0; entryIndex < entries.length; entryIndex++) {
          snapshot.entries.push(entries[entryIndex]);
        }
        status.success = true;
      } catch (error) {
        status.success = false;
        status.message = String(error);
        snapshot.overview.failedProviderCount += 1;
        logger.warn(TAG, `Provider扫描失败: ${provider.providerId}, ${String(error)}`);
      }
      status.durationMs = Date.now() - startedAt;
      snapshot.providerStatuses.push(status);
    }

    snapshot.entries.sort((left: ManagedStorageEntry, right: ManagedStorageEntry) => {
      if (left.group !== right.group) {
        return this.getGroupOrder(left.group) - this.getGroupOrder(right.group);
      }
      if (left.displayOrder !== right.displayOrder) {
        return left.displayOrder - right.displayOrder;
      }
      return right.sizeBytes - left.sizeBytes;
    });
    this.finalizeOverview(snapshot);

    this.cachedSnapshot = snapshot;
    this.cachedAt = now;
    return snapshot;
  }

  async clearEntries(abilityContext: common.UIAbilityContext, entryIds: string[], reason: string = 'manual'): Promise<ManagedStorageClearResult> {
    const request = new ManagedStorageClearRequest();
    request.entryIds = this.uniqueStrings(entryIds);
    request.reason = reason;
    const result = new ManagedStorageClearResult();
    const affectedProviders: ManagedStorageProvider[] = [];

    for (let index = 0; index < this.providers.length; index++) {
      const provider = this.providers[index];
      if (await this.providerHasAnyEntry(abilityContext, provider, request.entryIds)) {
        affectedProviders.push(provider);
      }
    }

    for (let index = 0; index < affectedProviders.length; index++) {
      const provider = affectedProviders[index];
      try {
        const providerResults = await provider.clear(abilityContext, request);
        for (let resultIndex = 0; resultIndex < providerResults.length; resultIndex++) {
          const item = providerResults[resultIndex];
          result.results.push(item);
          if (item.success) {
            result.clearedSizeBytes += item.clearedSizeBytes;
          } else {
            result.errors.push(`${item.title}: ${item.message}`);
          }
        }
      } catch (error) {
        const message = `${provider.title}: ${String(error)}`;
        result.errors.push(message);
      }
    }

    result.success = result.errors.length <= 0;
    this.cachedSnapshot = null;
    this.cachedAt = 0;
    return result;
  }

  async clearContentCache(
    abilityContext: common.UIAbilityContext,
    request: ManagedContentCacheClearRequest
  ): Promise<ManagedStorageClearResult> {
    const result = new ManagedStorageClearResult();
    const item = new ManagedStorageClearItemResult();
    item.id = `content_cache_${request.contentType}_${request.sourceId}_${request.contentId}`;
    item.title = request.title.length > 0 ? request.title : request.contentId;
    item.providerId = 'content_cache';

    if (request.contentId.length <= 0) {
      item.success = false;
      item.message = '内容ID为空';
      result.results.push(item);
      result.errors.push(item.message);
      return result;
    }

    try {
      const cacheStatusService = getCacheStatusService();
      cacheStatusService.setContext(abilityContext);
      const success = await cacheStatusService.clearContentCache(
        request.contentType,
        request.contentId,
        request.sourceId
      );
      item.success = success;
      item.clearedSizeBytes = success ? request.estimatedSizeBytes : 0;
      item.message = success ? '清理完成' : '清理失败';
      result.results.push(item);
      if (success) {
        result.success = true;
        result.clearedSizeBytes = item.clearedSizeBytes;
      } else {
        result.errors.push(`${item.title}: ${item.message}`);
      }
    } catch (error) {
      item.success = false;
      item.clearedSizeBytes = 0;
      item.message = String(error);
      result.results.push(item);
      result.errors.push(`${item.title}: ${item.message}`);
    }

    this.cachedSnapshot = null;
    this.cachedAt = 0;
    return result;
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

  private registerDefaultProviders(): void {
    this.providers = [];
    this.providers.push(new DefaultDirectoryStorageProvider());
    this.providers.push(new PreferenceManagedStorageProvider());
    this.providers.push(new RuntimeManagedStorageProvider());
    this.providers.push(new NetworkFolderManagedStorageProvider());
  }

  private async providerHasAnyEntry(
    abilityContext: common.UIAbilityContext,
    provider: ManagedStorageProvider,
    entryIds: string[]
  ): Promise<boolean> {
    try {
      const entries = await provider.inspect(abilityContext);
      for (let entryIndex = 0; entryIndex < entries.length; entryIndex++) {
        for (let idIndex = 0; idIndex < entryIds.length; idIndex++) {
          if (entries[entryIndex].id === entryIds[idIndex]) {
            return true;
          }
        }
      }
    } catch (error) {
      logger.warn(TAG, `判断Provider条目失败: ${provider.providerId}, ${String(error)}`);
    }
    return false;
  }

  private async loadOverviewBase(updatedAt: number): Promise<ManagedStorageOverview> {
    const overview = new ManagedStorageOverview();
    overview.updatedAt = updatedAt;
    try {
      const bundleStats = await storageStatistics.getCurrentBundleStats();
      overview.bundleAppSizeBytes = bundleStats.appSize;
      overview.bundleCacheSizeBytes = bundleStats.cacheSize;
      overview.bundleDataSizeBytes = bundleStats.dataSize;
      overview.bundleTotalSizeBytes = bundleStats.appSize + bundleStats.cacheSize + bundleStats.dataSize;
    } catch (error) {
      logger.warn(TAG, `读取应用存储统计失败: ${String(error)}`);
    }
    try {
      overview.deviceTotalSizeBytes = await storageStatistics.getTotalSize();
    } catch (error) {
      logger.debug(TAG, `读取设备总空间失败: ${String(error)}`);
    }
    try {
      overview.deviceFreeSizeBytes = await storageStatistics.getFreeSize();
    } catch (error) {
      logger.debug(TAG, `读取设备剩余空间失败: ${String(error)}`);
    }
    return overview;
  }

  private finalizeOverview(snapshot: ManagedStorageSnapshot): void {
    snapshot.overview.entryCount = snapshot.entries.length;
    for (let index = 0; index < snapshot.entries.length; index++) {
      const entry = snapshot.entries[index];
      if (entry.group === ManagedStorageGroup.RUNTIME_MEMORY) {
        snapshot.overview.memorySizeBytes += entry.sizeBytes;
      } else {
        snapshot.overview.scannedTotalSizeBytes += entry.sizeBytes;
      }
      if (entry.canClear || entry.canDelete) {
        snapshot.overview.reclaimableSizeBytes += entry.sizeBytes;
        snapshot.overview.reclaimableEntryCount += 1;
      }
      if (entry.risk === ManagedStorageRisk.DANGER) {
        snapshot.overview.dangerSizeBytes += entry.sizeBytes;
      }
      if (entry.risk === ManagedStorageRisk.PROTECTED) {
        snapshot.overview.protectedSizeBytes += entry.sizeBytes;
      }
    }
  }

  private getGroupOrder(group: ManagedStorageGroup): number {
    switch (group) {
      case ManagedStorageGroup.SAFE_CACHE:
        return 0;
      case ManagedStorageGroup.OFFLINE_CACHE:
        return 1;
      case ManagedStorageGroup.RUNTIME_MEMORY:
        return 2;
      case ManagedStorageGroup.TEMP_WORKSPACE:
        return 3;
      case ManagedStorageGroup.USER_DATA:
        return 4;
      case ManagedStorageGroup.BACKUP:
        return 5;
      case ManagedStorageGroup.EXTENSION:
        return 6;
      case ManagedStorageGroup.LOGS:
        return 7;
      case ManagedStorageGroup.DOWNLOAD_EXTERNAL:
        return 8;
      case ManagedStorageGroup.PROTECTED:
        return 9;
      default:
        return 99;
    }
  }

  private uniqueStrings(values: string[]): string[] {
    const result: string[] = [];
    for (let index = 0; index < values.length; index++) {
      let exists = false;
      for (let resultIndex = 0; resultIndex < result.length; resultIndex++) {
        if (result[resultIndex] === values[index]) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        result.push(values[index]);
      }
    }
    return result;
  }
}
