import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
/**
 * 在线漫画归档服务
 * 负责将在线下载/缓存的散图打包为 CBZ，并在阅读前解压到运行缓存目录。
 */

import { zlib } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import { MinizipNative } from '@ohos/minizip';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { MetadataXmlGenerator, MangaMetadata } from 'manxia_core/src/main/ets/Utils/MetadataXmlGenerator';
import { DataManager, OnlineChapterInfo, OnlineComicInfo, OnlinePageInfo } from '../Data/DataManager';
import { DatabaseManager } from 'manxia_core/src/main/ets/Framework/Database/DatabaseManager';
import { DatabaseValue, GenericQueryRecord } from 'manxia_core/src/main/ets/Framework/Database/DatabaseTypes';
import {
  DownloadDirManager,
  OnlineMangaArchiveLookupResult,
  OnlineMangaArchivePathRequest
} from '../Storage/DownloadDirManager';
import { PermanentImageCacheManager } from '../Cache/PermanentImageCacheManager';
import { generateDbId } from '../Utils/UUIDGenerator';
import { eventBus, GameEvent, MangaCacheUpdatedPayload } from '../EventBus';

const TAG = 'OnlineMangaArchiveService';

export enum OnlineArchiveMigrationStatus {
  MIGRATED = 'migrated',
  SKIPPED = 'skipped',
  FAILED = 'failed'
}

export interface OnlineArchivePageFile {
  pageIndex: number;
  imageUrl: string;
  sourcePath: string;
  width: number;
  height: number;
  fileSize: number;
}

export interface OnlineArchiveMetadata {
  sourceId: string;
  sourceName: string;
  sourcePkg: string;
  mangaId: string;
  mangaTitle: string;
  chapterId: string;
  chapterTitle: string;
  chapterUrl: string;
  author: string;
  description: string;
  coverUrl: string;
  tags: string[];
  lastUpdateTime: number;
  isPrivate: boolean;
  isNSFW: boolean;
}

export interface OnlineArchiveCreateRequest {
  sourceName: string;
  sourcePkg: string;
  mangaTitle: string;
  chapterTitle: string;
  mangaId: string;
  chapterId: string;
  pageFiles: OnlineArchivePageFile[];
  metadata: OnlineArchiveMetadata;
  preferPublicDownloadDir: boolean;
  totalPageCount?: number;       // 总页数（部分归档时需要）
  failedPageIndexes?: number[];  // 失败页索引列表（部分归档时需要）
}

export interface OnlineArchiveCreateResult {
  archivePath: string;
  archiveSize: number;
  pageCount: number;
}

export interface OnlineArchiveExtractRequest {
  archivePath: string;
  chapterId: string;
  pages: OnlinePageInfo[];
}

export interface OnlineArchiveExtractedPage {
  pageId: string;
  pageIndex: number;
  imageUrl: string;
  localPath: string;
  width: number;
  height: number;
  fileSize: number;
  isPlaceholder?: boolean;  // 是否为占位图（部分归档中的缺失页）
}

export interface OnlineArchiveExtractResult {
  extractDir: string;
  pages: OnlineArchiveExtractedPage[];
  reusedExtract: boolean;
}

export interface OnlineArchiveMigrationItem {
  chapterId: string;
  mangaTitle: string;
  chapterTitle: string;
  sourceName: string;
  status: OnlineArchiveMigrationStatus;
  message: string;
  archivePath: string;
  pageCount: number;
  archiveSize: number;
  migratedTime: number;
}

export interface OnlineArchiveMigrationSummary {
  totalCandidates: number;
  migratedCount: number;
  skippedCount: number;
  failedCount: number;
  totalArchiveSize: number;
  startedAt: number;
  completedAt: number;
  items: OnlineArchiveMigrationItem[];
}

interface LegacyPageFileBuildResult {
  pageFiles: OnlineArchivePageFile[];
  expectedPageCount: number;
  localPathRecordCount: number;
  missingLocalFileCount: number;
  recoveredCachePathCount: number;
  downloadPathImageCount: number;
}

interface OnlineArchiveSourceRecord {
  id: string;
  name: string;
  pkg: string;
  isNSFW: number;
}

interface FilesystemImageDirectory {
  directoryPath: string;
  imageFiles: string[];
}

interface FilesystemOrphanCandidate {
  scanKey: string;
  rootType: string;
  directoryPath: string;
  sourceId: string;
  sourceName: string;
  sourcePkg: string;
  mangaExternalId: string;
  chapterExternalId: string;
  preferredMangaId: string;
  preferredChapterId: string;
  mangaTitle: string;
  chapterTitle: string;
  chapterUrl: string;
  chapterNumber: number;
  pageFiles: OnlineArchivePageFile[];
  preferPublicDownloadDir: boolean;
  isPrivate: boolean;
  isNSFW: boolean;
}

interface ExistingOrphanChapterRecord {
  comicId: string;
  chapterId: string;
  pageCount: number;
  pageRecordCount: number;
  downloadPath: string;
}

interface ArchiveEntryReadInfo {
  entryNames: string[];
  comicInfoXml: string;
}

export enum OnlineChapterArchiveCacheStatus {
  NONE = 'none',
  PARTIAL = 'partial',
  COMPLETE = 'complete',
  STALE = 'stale'
}

export enum OnlineChapterArchiveStorageType {
  NONE = 'none',
  CBZ = 'cbz',
  LEGACY_PAGES = 'legacy_pages'
}

export interface OnlineArchiveCacheState {
  archivePath: string;
  archiveSize: number;
  totalPageCount: number;
  downloadedPageCount: number;
  failedPageIndexes: number[];
  isPartialArchive: boolean;
  hasComicInfo: boolean;
  imageEntryCount: number;
  cacheStatus: OnlineChapterArchiveCacheStatus;
  storageType: OnlineChapterArchiveStorageType;
}

export interface OnlineChapterArchiveCacheStateRecord {
  chapterId: string;
  comicId: string;
  sourceId: string;
  sourceName: string;
  sourcePkg: string;
  archivePath: string;
  cacheStatus: OnlineChapterArchiveCacheStatus;
  storageType: OnlineChapterArchiveStorageType;
  cachedPageCount: number;
  totalPageCount: number;
  archiveSize: number;
  imageEntryCount: number;
  hasComicInfo: boolean;
  failedPageIndexes: string;
  lastScanTime: number;
  createTime: number;
  updateTime: number;
}

export class OnlineMangaArchiveService {
  private static instance: OnlineMangaArchiveService | null = null;
  private context: common.UIAbilityContext | null = null;
  private dataManager: DataManager = DataManager.getInstance();
  private databaseManager: DatabaseManager = DatabaseManager.getInstance();
  private downloadDirManager: DownloadDirManager = DownloadDirManager.getInstance();
  private permanentCacheManager: PermanentImageCacheManager = PermanentImageCacheManager.getInstance();
  private readonly supportedImageExtensions: string[] = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'avif'];
  private activeReaderArchiveChapterIds: Set<string> = new Set<string>();
  private pendingReaderArchiveChapterIds: Set<string> = new Set<string>();
  private activeArchiveLocks: Set<string> = new Set<string>();
  private archiveLookupMissLogKeys: Set<string> = new Set<string>();
  private archiveTempSequence: number = 0;

  private constructor() {}

  public static getInstance(): OnlineMangaArchiveService {
    if (!OnlineMangaArchiveService.instance) {
      OnlineMangaArchiveService.instance = new OnlineMangaArchiveService();
    }
    return OnlineMangaArchiveService.instance;
  }

  public setContext(context: common.UIAbilityContext): void {
    this.context = context;
    this.downloadDirManager.setContext(context);
  }

  public hasContext(): boolean {
    return this.context !== null;
  }

  public fileExists(path: string): boolean {
    return this.pathExists(path);
  }

  public async getOnlineChapterArchiveCacheState(chapterId: string): Promise<OnlineChapterArchiveCacheStateRecord | null> {
    const rows = await this.databaseManager.querySql(
      'SELECT chapterId, comicId, sourceId, sourceName, sourcePkg, archivePath, cacheStatus, storageType, cachedPageCount, totalPageCount, archiveSize, imageEntryCount, hasComicInfo, failedPageIndexes, lastScanTime, createTime, updateTime FROM online_chapter_cache_state WHERE chapterId = ?',
      [chapterId]
    );
    if (rows.length <= 0) {
      return null;
    }
    return this.convertCacheStateRecord(rows[0] as GenericQueryRecord);
  }

  public async getOnlineComicArchiveCacheStates(comicId: string): Promise<OnlineChapterArchiveCacheStateRecord[]> {
    const rows = await this.databaseManager.querySql(
      'SELECT chapterId, comicId, sourceId, sourceName, sourcePkg, archivePath, cacheStatus, storageType, cachedPageCount, totalPageCount, archiveSize, imageEntryCount, hasComicInfo, failedPageIndexes, lastScanTime, createTime, updateTime FROM online_chapter_cache_state WHERE comicId = ?',
      [comicId]
    );
    const states: OnlineChapterArchiveCacheStateRecord[] = [];
    for (let i = 0; i < rows.length; i++) {
      states.push(this.convertCacheStateRecord(rows[i] as GenericQueryRecord));
    }
    return states;
  }

  public async syncOnlineComicArchiveStatus(comicId: string, reason: string = 'comic_archive_status_sync'): Promise<OnlineChapterArchiveCacheStateRecord[]> {
    const chapters = await this.dataManager.getOnlineComicChapters(comicId);
    const states: OnlineChapterArchiveCacheStateRecord[] = [];
    for (let i = 0; i < chapters.length; i++) {
      try {
        const archiveState = await this.syncOnlineChapterArchiveStatus(chapters[i].id, reason);
        const stateRecord = await this.getOnlineChapterArchiveCacheState(chapters[i].id);
        if (stateRecord !== null) {
          states.push(stateRecord);
        } else if (archiveState !== null) {
          // 状态表写入失败时尽量不让批量同步中断调用方。
          logger.warn(TAG, `在线章节缓存状态记录缺失: chapter=${chapters[i].id}, reason=${reason}`);
        }
      } catch (error) {
        logger.warn(TAG, `在线章节归档批量同步跳过单章: chapter=${chapters[i].id}, reason=${reason}, ${String(error)}`);
      }
      await this.yieldArchiveBatch(i);
    }
    return states;
  }

  public async clearOnlineComicArchiveCache(comicId: string): Promise<void> {
    const chapters = await this.dataManager.getOnlineComicChapters(comicId);
    const comic = await this.dataManager.getOnlineComicInfoById(comicId);
    const archivePaths: string[] = [];
    for (let i = 0; i < chapters.length; i++) {
      this.appendArchivePathForCleanup(archivePaths, chapters[i].downloadPath || '');
      const stateRecord = await this.getOnlineChapterArchiveCacheState(chapters[i].id);
      if (stateRecord !== null) {
        this.appendArchivePathForCleanup(archivePaths, stateRecord.archivePath);
      }
      const lookup = comic !== null
        ? this.resolveArchiveLookup(comic, chapters[i])
        : null;
      if (lookup !== null && lookup.archivePath.length > 0) {
        this.appendArchivePathForCleanup(archivePaths, lookup.archivePath);
      }
      await this.yieldArchiveBatch(i);
    }

    for (let i = 0; i < archivePaths.length; i++) {
      this.deleteFileIfExists(archivePaths[i]);
      this.deleteArchiveTempFiles(archivePaths[i]);
      logger.info(TAG, `已清理在线漫画CBZ缓存文件族: ${archivePaths[i]}`);
    }

    await this.databaseManager.beginTransaction();
    try {
      await this.databaseManager.executeSql(
        'DELETE FROM online_chapter_cache_state WHERE comicId = ?',
        [comicId]
      );
      await this.databaseManager.executeSql(
        'UPDATE online_chapter SET isDownloaded = 0, downloadPath = NULL, updateTime = ? WHERE comicId = ?',
        [Date.now(), comicId]
      );
      await this.databaseManager.executeSql(
        'UPDATE online_page SET isDownloaded = 0 WHERE chapterId IN (SELECT id FROM online_chapter WHERE comicId = ?)',
        [comicId]
      );
      await this.databaseManager.commit();
    } catch (error) {
      await this.databaseManager.rollBack();
      throw error as Error;
    }
    logger.info(TAG, `在线漫画归档缓存状态已清理: comicId=${comicId}, archives=${archivePaths.length}`);
  }

  private appendArchivePathForCleanup(paths: string[], rawPath: string): void {
    const normalizedPath = this.normalizeFileSystemPath(rawPath);
    if (normalizedPath.length <= 0 || !this.isCbzPath(normalizedPath)) {
      return;
    }
    if (!paths.includes(normalizedPath)) {
      paths.push(normalizedPath);
    }
  }

  private convertCacheStateRecord(row: GenericQueryRecord): OnlineChapterArchiveCacheStateRecord {
    const statusText = this.databaseValueToString(row.cacheStatus);
    const storageTypeText = this.databaseValueToString(row.storageType);
    const record: OnlineChapterArchiveCacheStateRecord = {
      chapterId: this.databaseValueToString(row.chapterId),
      comicId: this.databaseValueToString(row.comicId),
      sourceId: this.databaseValueToString(row.sourceId),
      sourceName: this.databaseValueToString(row.sourceName),
      sourcePkg: this.databaseValueToString(row.sourcePkg),
      archivePath: this.databaseValueToString(row.archivePath),
      cacheStatus: this.normalizeArchiveCacheStatus(statusText),
      storageType: this.normalizeArchiveStorageType(storageTypeText),
      cachedPageCount: this.databaseValueToNumber(row.cachedPageCount),
      totalPageCount: this.databaseValueToNumber(row.totalPageCount),
      archiveSize: this.databaseValueToNumber(row.archiveSize),
      imageEntryCount: this.databaseValueToNumber(row.imageEntryCount),
      hasComicInfo: this.databaseValueToNumber(row.hasComicInfo) === 1,
      failedPageIndexes: this.databaseValueToString(row.failedPageIndexes),
      lastScanTime: this.databaseValueToNumber(row.lastScanTime),
      createTime: this.databaseValueToNumber(row.createTime),
      updateTime: this.databaseValueToNumber(row.updateTime)
    };
    return record;
  }

  private normalizeArchiveCacheStatus(value: string): OnlineChapterArchiveCacheStatus {
    if (value === OnlineChapterArchiveCacheStatus.COMPLETE) {
      return OnlineChapterArchiveCacheStatus.COMPLETE;
    }
    if (value === OnlineChapterArchiveCacheStatus.PARTIAL) {
      return OnlineChapterArchiveCacheStatus.PARTIAL;
    }
    if (value === OnlineChapterArchiveCacheStatus.STALE) {
      return OnlineChapterArchiveCacheStatus.STALE;
    }
    return OnlineChapterArchiveCacheStatus.NONE;
  }

  private normalizeArchiveStorageType(value: string): OnlineChapterArchiveStorageType {
    if (value === OnlineChapterArchiveStorageType.CBZ) {
      return OnlineChapterArchiveStorageType.CBZ;
    }
    if (value === OnlineChapterArchiveStorageType.LEGACY_PAGES) {
      return OnlineChapterArchiveStorageType.LEGACY_PAGES;
    }
    return OnlineChapterArchiveStorageType.NONE;
  }

  private databaseValueToString(value: DatabaseValue | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    return String(value);
  }

  private databaseValueToNumber(value: DatabaseValue | undefined): number {
    if (value === undefined || value === null) {
      return 0;
    }
    if (typeof value === 'number') {
      return this.isUsableNumber(value) ? Math.floor(value) : 0;
    }
    const parsed = Number(String(value));
    return this.isUsableNumber(parsed) ? Math.floor(parsed) : 0;
  }

  private isUsableNumber(value: number): boolean {
    return value === value && value !== Infinity && value !== -Infinity;
  }

  public async resolveExistingArchiveForOnlineChapter(chapterId: string): Promise<string> {
    const archiveState = await this.syncOnlineChapterArchiveStatus(chapterId, 'resolve_existing_archive');
    return archiveState ? archiveState.archivePath : '';
  }

  public async syncOnlineChapterArchiveStatus(
    chapterId: string,
    reason: string = 'archive_status_sync'
  ): Promise<OnlineArchiveCacheState | null> {
    let stage = 'normalize';
    const normalizedChapterId = chapterId.trim();
    if (normalizedChapterId.length === 0) {
      return null;
    }

    try {
      stage = 'load_chapter';
      const chapter = await this.dataManager.getOnlineChapterById(normalizedChapterId);
      if (!chapter) {
        logger.warn(TAG, `归档状态同步跳过：章节不存在 chapterId=${normalizedChapterId}`);
        return null;
      }

      stage = 'load_comic';
      const comic = await this.dataManager.getOnlineComicInfoById(chapter.comicId);
      if (!comic) {
        logger.warn(TAG, `归档状态同步跳过：漫画不存在 comicId=${chapter.comicId}`);
        return null;
      }

      stage = 'resolve_stored_download_path';
      let archivePath = this.resolveArchivePathFromStoredDownloadPath(chapter.downloadPath || '', chapter);

      stage = 'resolve_download_directory_archive';
      if (archivePath.length <= 0) {
        archivePath = await this.resolveExistingArchiveForChapter(comic, chapter);
      }

      if (archivePath.length <= 0) {
        stage = 'persist_miss_state';
        await this.persistOnlineArchiveLookupMiss(comic, chapter, reason);
        await this.logArchiveLookupMiss(comic, chapter, reason);
        return null;
      }

      stage = 'resolve_known_page_count';
      const knownPageCount = await this.resolveKnownOnlineChapterPageCount(chapter.id);
      stage = 'inspect_archive';
      const archiveState = this.inspectArchiveCacheState(archivePath, chapter, knownPageCount);
      stage = 'persist_archive_state';
      await this.persistOnlineArchiveCacheState(comic, chapter, archiveState);
      logger.info(
        TAG,
        `在线章节归档状态已同步: chapter=${chapter.title}, status=${archiveState.cacheStatus}, pages=${archiveState.downloadedPageCount}/${archiveState.totalPageCount}, reason=${reason}, path=${archiveState.archivePath}`
      );
      return archiveState;
    } catch (error) {
      logger.warn(TAG, `同步在线章节归档状态失败: chapterId=${normalizedChapterId}, stage=${stage}, reason=${reason}, ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 生成最小占位PNG图片（白色1x1像素，约67字节）
   * 用于部分归档中缺失的页面位置
   */
  private async generatePlaceholderPng(targetPath: string): Promise<void> {
    // 最小合法PNG: 1x1 白色像素
    const placeholder = new Uint8Array([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR length + type
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, // 8-bit RGB
      0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, // IDAT length + type
      0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, // compressed data
      0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, //
      0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, // IEND length + type
      0x44, 0xAE, 0x42, 0x60, 0x82                    // IEND CRC
    ]);
    await this.writeArrayBufferToFile(targetPath, placeholder.buffer as ArrayBuffer);
  }

  public async createArchiveFromPageFiles(request: OnlineArchiveCreateRequest): Promise<OnlineArchiveCreateResult> {
    if (request.pageFiles.length === 0) {
      throw new Error('归档页面不能为空');
    }

    const isPartialArchive = request.failedPageIndexes !== undefined
      && request.failedPageIndexes.length > 0
      && request.totalPageCount !== undefined
      && request.totalPageCount > request.pageFiles.length;

    const archivePath = this.resolveArchivePath(request);
    const lockKey = this.buildArchiveLockKey(request.chapterId, archivePath);
    await this.acquireArchiveLock(lockKey);
    let workDir = '';
    try {
      workDir = this.createWorkDir(request.chapterId);
      const sortedPages = request.pageFiles.slice().sort((left: OnlineArchivePageFile, right: OnlineArchivePageFile) => {
        return left.pageIndex - right.pageIndex;
      });

      if (isPartialArchive) {
        // 部分归档：按总页数创建完整序列，缺失页用占位图填充
        const totalPageCount = request.totalPageCount !== undefined ? request.totalPageCount : sortedPages.length;
        const failedPageIndexes = request.failedPageIndexes !== undefined ? request.failedPageIndexes : [];
        const failedSet = new Set(failedPageIndexes);
        let realPageIdx = 0;

        for (let i = 0; i < totalPageCount; i++) {
          const targetPath = `${workDir}/${String(i + 1).padStart(4, '0')}.png`;
          if (failedSet.has(i)) {
            // 失败页：生成占位图
            await this.generatePlaceholderPng(targetPath);
          } else {
            // 成功页：从已下载的页面中取
            if (realPageIdx < sortedPages.length) {
              const page = sortedPages[realPageIdx];
              if (!this.pathExists(page.sourcePath)) {
                await this.generatePlaceholderPng(targetPath);
              } else {
                const extension = this.resolveImageExtension(page.sourcePath, page.imageUrl);
                const finalTarget = `${workDir}/${String(i + 1).padStart(4, '0')}.${extension}`;
                await fs.copyFile(page.sourcePath, finalTarget);
              }
              realPageIdx++;
            } else {
              await this.generatePlaceholderPng(targetPath);
            }
          }
          await this.yieldArchiveBatch(i);
        }

        const comicInfoXml = this.buildComicInfoXml(request.metadata, totalPageCount, failedPageIndexes);
        await this.writeTextFile(`${workDir}/ComicInfo.xml`, comicInfoXml);

        const tempArchivePath = this.buildUniqueTempArchivePath(archivePath);
        const legacyTempArchivePath = `${archivePath}.tmp`;
        this.deleteArchiveTempFiles(archivePath);
        this.deleteUniqueArchiveTempFiles(tempArchivePath);

        await zlib.compressFile(workDir, tempArchivePath, {
          level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
          memLevel: zlib.MemLevel.MEM_LEVEL_DEFAULT,
          strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY
        });
        const compressedOutputPath = this.resolveCompressedOutputPath(tempArchivePath, legacyTempArchivePath);
        this.deleteFileIfExists(archivePath);
        await fs.rename(compressedOutputPath, archivePath);
        this.deleteUniqueArchiveTempFiles(tempArchivePath);
        this.deleteArchiveTempFiles(archivePath);

        const archiveSize = this.getFileSize(archivePath);
        logger.info(TAG, `在线漫画CBZ部分归档完成: ${archivePath}, pages=${sortedPages.length}/${totalPageCount}, failed=${failedPageIndexes.length}, size=${archiveSize}`);
        return {
          archivePath: archivePath,
          archiveSize: archiveSize,
          pageCount: totalPageCount
        };
      } else {
        // 完整归档：原有逻辑
        for (let i = 0; i < sortedPages.length; i++) {
          const page = sortedPages[i];
          if (!this.pathExists(page.sourcePath)) {
            throw new Error(`页面文件不存在: ${page.sourcePath}`);
          }
          const extension = this.resolveImageExtension(page.sourcePath, page.imageUrl);
          const targetPath = `${workDir}/${String(i + 1).padStart(4, '0')}.${extension}`;
          await fs.copyFile(page.sourcePath, targetPath);
          await this.yieldArchiveBatch(i);
        }

        const comicInfoXml = this.buildComicInfoXml(request.metadata, sortedPages.length);
        await this.writeTextFile(`${workDir}/ComicInfo.xml`, comicInfoXml);

        const tempArchivePath = this.buildUniqueTempArchivePath(archivePath);
        const legacyTempArchivePath = `${archivePath}.tmp`;
        this.deleteArchiveTempFiles(archivePath);
        this.deleteUniqueArchiveTempFiles(tempArchivePath);

        await zlib.compressFile(workDir, tempArchivePath, {
          level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
          memLevel: zlib.MemLevel.MEM_LEVEL_DEFAULT,
          strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY
        });
        const compressedOutputPath = this.resolveCompressedOutputPath(tempArchivePath, legacyTempArchivePath);
        this.deleteFileIfExists(archivePath);
        await fs.rename(compressedOutputPath, archivePath);
        this.deleteUniqueArchiveTempFiles(tempArchivePath);
        this.deleteArchiveTempFiles(archivePath);

        const archiveSize = this.getFileSize(archivePath);
        logger.info(TAG, `在线漫画CBZ归档完成: ${archivePath}, pages=${sortedPages.length}, size=${archiveSize}`);
        return {
          archivePath: archivePath,
          archiveSize: archiveSize,
          pageCount: sortedPages.length
        };
      }
    } finally {
      if (workDir.length > 0) {
        await this.deleteDirectoryRecursiveAsync(workDir);
      }
      this.releaseArchiveLock(lockKey);
    }
  }

  public async extractArchiveForReader(request: OnlineArchiveExtractRequest): Promise<OnlineArchiveExtractResult> {
    if (!request.archivePath || !this.isCbzPath(request.archivePath)) {
      throw new Error(`无效的CBZ路径: ${request.archivePath}`);
    }
    if (!this.pathExists(request.archivePath)) {
      throw new Error(`CBZ文件不存在: ${request.archivePath}`);
    }

    const extractDir = this.resolveReaderExtractDir(request.chapterId, request.archivePath);
    const reusedExtract: boolean = this.hasReadableExtractedImages(extractDir);
    if (!reusedExtract) {
      await this.deleteDirectoryRecursiveAsync(extractDir);
      this.ensureDirectory(extractDir);
      await zlib.decompressFile(request.archivePath, extractDir);
      logger.info(TAG, `在线漫画CBZ已解压: ${request.archivePath} -> ${extractDir}`);
    } else {
      logger.debug(TAG, `在线漫画CBZ复用已解压目录: ${request.archivePath} -> ${extractDir}`);
    }

    const imageFiles = this.scanImageFilesRecursive(extractDir);
    const pages: OnlineArchiveExtractedPage[] = [];
    const pageInfos = request.pages.slice().sort((left: OnlinePageInfo, right: OnlinePageInfo) => {
      return left.pageNumber - right.pageNumber;
    });
    const archiveReadInfo = this.readArchiveEntryInfo(request.archivePath);
    const archiveXmlPageCount = archiveReadInfo.comicInfoXml.length > 0
      ? this.parsePositiveIntegerXmlField(archiveReadInfo.comicInfoXml, 'PageCount')
      : 0;
    const rawArchiveFailedPageIndexes = archiveReadInfo.comicInfoXml.length > 0
      ? this.parseFailedPageIndexes(archiveReadInfo.comicInfoXml)
      : [];
    const totalOutputPageCount = pageInfos.length > 0
      ? Math.max(pageInfos.length, imageFiles.length, archiveXmlPageCount)
      : imageFiles.length;
    const archiveFailedPageIndexes = this.normalizeFailedPageIndexesForTotal(
      rawArchiveFailedPageIndexes,
      totalOutputPageCount
    );
    if (pageInfos.length <= 0 && archiveXmlPageCount > imageFiles.length) {
      logger.warn(
        TAG,
        `部分CBZ缺少在线页表，无法生成缺页网络地址: archive=${request.archivePath}, images=${imageFiles.length}, xmlPages=${archiveXmlPageCount}`
      );
    }
    const hasFullImageSequence = totalOutputPageCount > 0 && imageFiles.length >= totalOutputPageCount;
    let imageCursor = 0;

    // 检测是否为部分归档（占位图文件大小通常 <= 200 字节）
    const PLACEHOLDER_SIZE_THRESHOLD = 200;

    for (let i = 0; i < totalOutputPageCount; i++) {
      const pageInfo = i < pageInfos.length ? pageInfos[i] : null;
      const isMarkedFailed = archiveFailedPageIndexes.includes(i);
      let localPath = '';
      if (hasFullImageSequence) {
        localPath = i < imageFiles.length ? imageFiles[i] : '';
      } else if (!isMarkedFailed && imageCursor < imageFiles.length) {
        localPath = imageFiles[imageCursor];
        imageCursor++;
      }
      const hasLocalFile = localPath.length > 0;
      const fileSize = hasLocalFile ? this.getFileSize(localPath) : 0;
      const isPlaceholder = isMarkedFailed || !hasLocalFile ||
        (fileSize > 0 && fileSize <= PLACEHOLDER_SIZE_THRESHOLD);
      const page: OnlineArchiveExtractedPage = {
        pageId: pageInfo ? pageInfo.id : `${request.chapterId}_archive_${i}`,
        pageIndex: i,
        imageUrl: pageInfo ? pageInfo.imageUrl : localPath,
        localPath: isPlaceholder ? '' : localPath,
        width: pageInfo ? pageInfo.width : 0,
        height: pageInfo ? pageInfo.height : 0,
        fileSize: fileSize,
        isPlaceholder: isPlaceholder
      };
      pages.push(page);
    }

    if (pages.length === 0) {
      throw new Error(`CBZ解压后未找到图片: ${request.archivePath}`);
    }

    return {
      extractDir: extractDir,
      pages: pages,
      reusedExtract: reusedExtract
    };
  }

  public async tryArchiveCachedOnlineChapter(
    chapterId: string,
    reason: string = 'reader_cache_complete'
  ): Promise<OnlineArchiveCreateResult | null> {
    const normalizedChapterId = chapterId.trim();
    if (normalizedChapterId.length === 0) {
      return null;
    }

    if (this.activeReaderArchiveChapterIds.has(normalizedChapterId)) {
      this.pendingReaderArchiveChapterIds.add(normalizedChapterId);
      return null;
    }

    this.activeReaderArchiveChapterIds.add(normalizedChapterId);
    try {
      return await this.tryArchiveCachedOnlineChapterInternal(normalizedChapterId, reason);
    } finally {
      this.activeReaderArchiveChapterIds.delete(normalizedChapterId);
      if (this.pendingReaderArchiveChapterIds.has(normalizedChapterId)) {
        this.pendingReaderArchiveChapterIds.delete(normalizedChapterId);
        this.retryArchiveCachedOnlineChapter(normalizedChapterId, reason);
      }
    }
  }

  public enqueueArchiveCachedOnlineChapter(
    chapterId: string,
    reason: string = 'reader_cache_complete'
  ): void {
    const normalizedChapterId = chapterId.trim();
    if (normalizedChapterId.length === 0) {
      return;
    }
    logger.debug(TAG, `阅读缓存归档已投递: chapterId=${normalizedChapterId}, reason=${reason}`);
    this.retryArchiveCachedOnlineChapter(normalizedChapterId, reason);
  }

  private async tryArchiveCachedOnlineChapterInternal(
    chapterId: string,
    reason: string
  ): Promise<OnlineArchiveCreateResult | null> {
    try {
      const chapter = await this.dataManager.getOnlineChapterById(chapterId);
      if (!chapter) {
        logger.warn(TAG, `阅读缓存归档跳过：章节记录不存在 chapterId=${chapterId}`);
        return null;
      }

      const comic = await this.dataManager.getOnlineComicInfoById(chapter.comicId);
      if (!comic) {
        logger.warn(TAG, `阅读缓存归档跳过：漫画记录不存在 comicId=${chapter.comicId}`);
        return null;
      }

      const pageInfos = await this.dataManager.getOnlineChapterPages(chapter.id);
      const expectedPageCount = Math.max(pageInfos.length, chapter.pageCount || 0);
      const currentArchivePath = this.normalizeFileSystemPath(chapter.downloadPath || '');
      if (currentArchivePath.length > 0 && this.isCbzPath(currentArchivePath) && this.pathExists(currentArchivePath)) {
        const archiveState = await this.syncOnlineChapterArchiveStatus(chapter.id, 'reader_existing_archive');
        if (!chapter.isDownloaded || (archiveState !== null && archiveState.isPartialArchive)) {
          this.publishMangaCacheUpdated(comic, chapter, currentArchivePath, reason);
        }
        return {
          archivePath: currentArchivePath,
          archiveSize: this.getFileSize(currentArchivePath),
          pageCount: archiveState ? archiveState.totalPageCount : expectedPageCount
        };
      }

      if (expectedPageCount <= 0) {
        logger.debug(TAG, `阅读缓存归档跳过：章节页数未知 chapter=${chapter.title}`);
        return null;
      }

      const recoveredArchivePath = await this.resolveExistingArchiveForChapter(comic, chapter);
      if (recoveredArchivePath.length > 0) {
        const archiveState = await this.syncOnlineChapterArchiveStatus(chapter.id, 'reader_recovered_archive');
        const recoveredPageCount = archiveState
          ? archiveState.totalPageCount
          : Math.max(expectedPageCount, chapter.pageCount || 0);
        this.publishMangaCacheUpdated(comic, chapter, recoveredArchivePath, reason);
        logger.info(TAG, `阅读缓存归档恢复已有CBZ: chapter=${chapter.title}, path=${recoveredArchivePath}`);
        return {
          archivePath: recoveredArchivePath,
          archiveSize: this.getFileSize(recoveredArchivePath),
          pageCount: recoveredPageCount
        };
      }

      const buildResult = await this.buildLegacyPageFiles(pageInfos, comic, chapter);
      if (buildResult.pageFiles.length < expectedPageCount) {
        logger.debug(
          TAG,
          `阅读缓存归档等待散图补齐: chapter=${chapter.title}, pages=${buildResult.pageFiles.length}/${expectedPageCount}, recovered=${buildResult.recoveredCachePathCount}`
        );
        return null;
      }

      const metadata = this.buildMetadataFromComic(comic, chapter);
      const result = await this.createArchiveFromPageFiles({
        sourceName: comic.sourceName,
        sourcePkg: comic.sourcePkg,
        mangaTitle: comic.title,
        chapterTitle: chapter.title,
        mangaId: comic.id,
        chapterId: chapter.id,
        pageFiles: buildResult.pageFiles,
        metadata: metadata,
        preferPublicDownloadDir: true
      });

      await this.markOnlineChapterArchived(chapter.id, result.archivePath, result.pageCount);
      await this.syncOnlineChapterArchiveStatus(chapter.id, 'reader_archive_created_state_sync');
      this.publishMangaCacheUpdated(comic, chapter, result.archivePath, reason);
      logger.info(TAG, `阅读缓存已归档为CBZ: chapter=${chapter.title}, path=${result.archivePath}`);
      return result;
    } catch (error) {
      logger.warn(TAG, `阅读缓存归档检查失败: chapterId=${chapterId}, ${String(error)}`);
      return null;
    }
  }

  private retryArchiveCachedOnlineChapter(chapterId: string, reason: string): void {
    (async () => {
      await this.tryArchiveCachedOnlineChapter(chapterId, reason);
    })().catch((error: Error) => {
      logger.warn(TAG, `阅读缓存归档重试失败: chapterId=${chapterId}, ${String(error)}`);
    });
  }

  private async markOnlineChapterArchived(
    chapterId: string,
    archivePath: string,
    pageCount: number,
    markAllPages: boolean = true
  ): Promise<void> {
    await this.databaseManager.executeSql(
      'UPDATE online_chapter SET isDownloaded = 1, downloadPath = ?, pageCount = ?, updateTime = ? WHERE id = ?',
      [archivePath, pageCount, Date.now(), chapterId]
    );
    if (markAllPages) {
      await this.databaseManager.executeSql(
        'UPDATE online_page SET isDownloaded = 1 WHERE chapterId = ?',
        [chapterId]
      );
    }
  }

  private publishMangaCacheUpdated(
    comic: OnlineComicInfo,
    chapter: OnlineChapterInfo,
    archivePath: string,
    reason: string
  ): void {
    const numericSourceId = Number(comic.sourceId);
    const sourceId = this.isUsableNumber(numericSourceId) ? numericSourceId : 0;
    eventBus.publish(
      GameEvent.MANGA_CACHE_UPDATED,
      new MangaCacheUpdatedPayload(
        comic.id,
        chapter.id,
        sourceId,
        archivePath,
        reason
      )
    );
  }

  public async runLegacyCacheMigration(): Promise<OnlineArchiveMigrationSummary> {
    const startedAt = Date.now();
    const summary: OnlineArchiveMigrationSummary = {
      totalCandidates: 0,
      migratedCount: 0,
      skippedCount: 0,
      failedCount: 0,
      totalArchiveSize: 0,
      startedAt: startedAt,
      completedAt: 0,
      items: []
    };

    try {
      const chapterIds = await this.queryLegacyLooseCacheChapterIds();
      summary.totalCandidates += chapterIds.length;

      for (let i = 0; i < chapterIds.length; i++) {
        const item = await this.migrateSingleLegacyChapter(chapterIds[i]);
        this.appendMigrationItem(summary, item);
      }

      const orphanItems = await this.runFilesystemOrphanMigration();
      summary.totalCandidates += orphanItems.length;
      for (let i = 0; i < orphanItems.length; i++) {
        this.appendMigrationItem(summary, orphanItems[i]);
      }
    } catch (error) {
      logger.error(TAG, `旧缓存迁移失败: ${String(error)}`);
    } finally {
      summary.completedAt = Date.now();
    }

    logger.info(TAG, `旧缓存迁移完成: total=${summary.totalCandidates}, migrated=${summary.migratedCount}, skipped=${summary.skippedCount}, failed=${summary.failedCount}`);
    return summary;
  }

  private appendMigrationItem(summary: OnlineArchiveMigrationSummary, item: OnlineArchiveMigrationItem): void {
    summary.items.push(item);
    if (item.status === OnlineArchiveMigrationStatus.MIGRATED) {
      summary.migratedCount++;
      summary.totalArchiveSize += item.archiveSize;
    } else if (item.status === OnlineArchiveMigrationStatus.SKIPPED) {
      summary.skippedCount++;
    } else {
      summary.failedCount++;
    }
  }

  private async migrateSingleLegacyChapter(chapterId: string): Promise<OnlineArchiveMigrationItem> {
    const fallbackItem: OnlineArchiveMigrationItem = {
      chapterId: chapterId,
      mangaTitle: '',
      chapterTitle: '',
      sourceName: '',
      status: OnlineArchiveMigrationStatus.FAILED,
      message: '',
      archivePath: '',
      pageCount: 0,
      archiveSize: 0,
      migratedTime: Date.now()
    };

    try {
      const chapter = await this.dataManager.getOnlineChapterById(chapterId);
      if (!chapter) {
        fallbackItem.message = '章节记录不存在';
        return fallbackItem;
      }
      fallbackItem.chapterTitle = chapter.title;

      const comic = await this.dataManager.getOnlineComicInfoById(chapter.comicId);
      if (!comic) {
        fallbackItem.message = '漫画记录不存在';
        return fallbackItem;
      }
      fallbackItem.mangaTitle = comic.title;
      fallbackItem.sourceName = comic.sourceName || comic.sourcePkg || `source_${comic.sourceId}`;

      if (chapter.downloadPath && this.isCbzPath(chapter.downloadPath) && this.pathExists(chapter.downloadPath)) {
        fallbackItem.status = OnlineArchiveMigrationStatus.SKIPPED;
        fallbackItem.message = '章节已存在有效CBZ归档';
        fallbackItem.archivePath = chapter.downloadPath;
        fallbackItem.archiveSize = this.getFileSize(chapter.downloadPath);
        fallbackItem.pageCount = chapter.pageCount;
        return fallbackItem;
      }

      const pageInfos = await this.dataManager.getOnlineChapterPages(chapter.id);
      const recoveredArchivePath = await this.resolveExistingArchiveForChapter(comic, chapter);
      if (recoveredArchivePath.length > 0) {
        const archiveState = await this.syncOnlineChapterArchiveStatus(chapter.id, 'legacy_migration_recovered_archive');
        const recoveredPageCount = archiveState
          ? archiveState.totalPageCount
          : Math.max(pageInfos.length, chapter.pageCount || 0);

        fallbackItem.status = OnlineArchiveMigrationStatus.MIGRATED;
        fallbackItem.message = archiveState && archiveState.isPartialArchive
          ? '已恢复部分CBZ归档'
          : '已恢复完整CBZ归档';
        fallbackItem.archivePath = recoveredArchivePath;
        fallbackItem.archiveSize = this.getFileSize(recoveredArchivePath);
        fallbackItem.pageCount = recoveredPageCount;
        fallbackItem.migratedTime = Date.now();
        return fallbackItem;
      }

      const buildResult = await this.buildLegacyPageFiles(pageInfos, comic, chapter);
      const pageFiles = buildResult.pageFiles;
      if (pageFiles.length === 0) {
        fallbackItem.status = OnlineArchiveMigrationStatus.SKIPPED;
        fallbackItem.message = `未找到可迁移的本地散图，数据库本地路径=${buildResult.localPathRecordCount}，不可访问=${buildResult.missingLocalFileCount}，兜底恢复=${buildResult.recoveredCachePathCount}，章节目录图片=${buildResult.downloadPathImageCount}`;
        return fallbackItem;
      }
      if (buildResult.expectedPageCount > 0 && pageFiles.length < buildResult.expectedPageCount) {
        fallbackItem.status = OnlineArchiveMigrationStatus.SKIPPED;
        fallbackItem.message = `散图不完整，已找到 ${pageFiles.length}/${buildResult.expectedPageCount} 页，兜底恢复=${buildResult.recoveredCachePathCount}，章节目录图片=${buildResult.downloadPathImageCount}，需补齐后再迁移`;
        fallbackItem.pageCount = pageFiles.length;
        return fallbackItem;
      }

      const metadata = this.buildMetadataFromComic(comic, chapter);
      const createRequest: OnlineArchiveCreateRequest = {
        sourceName: comic.sourceName,
        sourcePkg: comic.sourcePkg,
        mangaTitle: comic.title,
        chapterTitle: chapter.title,
        mangaId: comic.id,
        chapterId: chapter.id,
        pageFiles: pageFiles,
        metadata: metadata,
        preferPublicDownloadDir: true
      };
      const result = await this.createArchiveFromPageFiles(createRequest);

      await this.databaseManager.executeSql(
        'UPDATE online_chapter SET isDownloaded = 1, downloadPath = ?, pageCount = ?, updateTime = ? WHERE id = ?',
        [result.archivePath, result.pageCount, Date.now(), chapter.id]
      );
      await this.databaseManager.executeSql(
        'UPDATE online_page SET isDownloaded = 1 WHERE chapterId = ?',
        [chapter.id]
      );
      await this.syncOnlineChapterArchiveStatus(chapter.id, 'legacy_migration_created_archive_state_sync');

      fallbackItem.status = OnlineArchiveMigrationStatus.MIGRATED;
      fallbackItem.message = '迁移完成';
      fallbackItem.archivePath = result.archivePath;
      fallbackItem.pageCount = result.pageCount;
      fallbackItem.archiveSize = result.archiveSize;
      fallbackItem.migratedTime = Date.now();
      return fallbackItem;
    } catch (error) {
      fallbackItem.status = OnlineArchiveMigrationStatus.FAILED;
      fallbackItem.message = String(error);
      fallbackItem.migratedTime = Date.now();
      logger.warn(TAG, `迁移章节失败: chapterId=${chapterId}, error=${String(error)}`);
      return fallbackItem;
    }
  }

  private async queryLegacyLooseCacheChapterIds(): Promise<string[]> {
    const sql = `
      SELECT DISTINCT oc.id
      FROM online_chapter oc
      LEFT JOIN online_page op ON op.chapterId = oc.id
      WHERE (op.localPath IS NOT NULL AND op.localPath != '')
        OR (oc.isDownloaded = 0 AND op.isDownloaded = 1)
        OR (
          oc.downloadPath IS NOT NULL
          AND oc.downloadPath != ''
          AND lower(oc.downloadPath) NOT LIKE '%.cbz'
        )
    `;
    const records = await this.databaseManager.querySql(sql, []);
    const chapterIds: string[] = [];
    for (let i = 0; i < records.length; i++) {
      const record = records[i] as GenericQueryRecord;
      const chapterId = record.chapterId ? String(record.chapterId) : (record.id ? String(record.id) : '');
      if (chapterId.length > 0) {
        chapterIds.push(chapterId);
      }
    }
    return chapterIds;
  }

  private async buildLegacyPageFiles(
    pageInfos: OnlinePageInfo[],
    comic: OnlineComicInfo,
    chapter: OnlineChapterInfo
  ): Promise<LegacyPageFileBuildResult> {
    const sortedPages = pageInfos.slice().sort((left: OnlinePageInfo, right: OnlinePageInfo) => {
      return left.pageNumber - right.pageNumber;
    });
    let pageFiles: OnlineArchivePageFile[] = [];
    let localPathRecordCount = 0;
    let missingLocalFileCount = 0;
    let recoveredCachePathCount = 0;
    let downloadPathImageCount = 0;

    for (let i = 0; i < sortedPages.length; i++) {
      const page = sortedPages[i];
      const rawLocalPath = page.localPath || '';
      if (rawLocalPath.length > 0) {
        localPathRecordCount++;
      }
      const resolvedPath = await this.resolveLegacyPageFilePath(page, comic, chapter);
      if (resolvedPath.length === 0) {
        if (rawLocalPath.length > 0) {
          missingLocalFileCount++;
        }
        continue;
      }
      if (rawLocalPath.length > 0 && this.normalizeFileSystemPath(rawLocalPath) !== resolvedPath) {
        recoveredCachePathCount++;
      }
      const pageFile: OnlineArchivePageFile = {
        pageIndex: i,
        imageUrl: page.imageUrl,
        sourcePath: resolvedPath,
        width: page.width,
        height: page.height,
        fileSize: page.fileSize || this.getFileSize(resolvedPath)
      };
      pageFiles.push(pageFile);
    }

    const downloadPathPageFiles = this.buildLegacyPageFilesFromDownloadPath(chapter, sortedPages);
    downloadPathImageCount = downloadPathPageFiles.length;
    if (downloadPathPageFiles.length > pageFiles.length) {
      pageFiles = downloadPathPageFiles;
    }

    return {
      pageFiles: pageFiles,
      expectedPageCount: Math.max(sortedPages.length, chapter.pageCount || 0),
      localPathRecordCount: localPathRecordCount,
      missingLocalFileCount: missingLocalFileCount,
      recoveredCachePathCount: recoveredCachePathCount,
      downloadPathImageCount: downloadPathImageCount
    };
  }

  private buildLegacyPageFilesFromDownloadPath(
    chapter: OnlineChapterInfo,
    sortedPages: OnlinePageInfo[]
  ): OnlineArchivePageFile[] {
    const downloadPath = this.normalizeFileSystemPath(chapter.downloadPath || '');
    if (downloadPath.length === 0 || this.isCbzPath(downloadPath) || !this.pathExists(downloadPath)) {
      return [];
    }

    try {
      const stat = SafeFileUtils.statSync(downloadPath);
      if (!stat.isDirectory()) {
        return [];
      }
      const imageFiles = this.scanImageFilesRecursive(downloadPath);
      const pageFiles: OnlineArchivePageFile[] = [];
      for (let i = 0; i < imageFiles.length; i++) {
        const pageInfo = i < sortedPages.length ? sortedPages[i] : null;
        const imagePath = imageFiles[i];
        const pageFile: OnlineArchivePageFile = {
          pageIndex: i,
          imageUrl: pageInfo ? pageInfo.imageUrl : imagePath,
          sourcePath: imagePath,
          width: pageInfo ? pageInfo.width : 0,
          height: pageInfo ? pageInfo.height : 0,
          fileSize: pageInfo && pageInfo.fileSize > 0 ? pageInfo.fileSize : this.getFileSize(imagePath)
        };
        pageFiles.push(pageFile);
      }
      return pageFiles;
    } catch (error) {
      logger.warn(TAG, `扫描章节散图目录失败: ${downloadPath}, ${String(error)}`);
      return [];
    }
  }

  private async resolveLegacyPageFilePath(
    page: OnlinePageInfo,
    comic: OnlineComicInfo,
    chapter: OnlineChapterInfo
  ): Promise<string> {
    const localPath = this.normalizeFileSystemPath(page.localPath || '');
    if (localPath.length > 0 && this.pathExists(localPath)) {
      return localPath;
    }

    const sourceNumericId = Number(comic.sourceId);
    if (!this.isUsableNumber(sourceNumericId)) {
      return '';
    }

    const cachedPath = await this.permanentCacheManager.getCachedImagePath(
      sourceNumericId,
      comic.id,
      chapter.id,
      page.pageNumber,
      page.imageUrl
    );
    if (cachedPath && cachedPath.length > 0 && this.pathExists(cachedPath)) {
      return cachedPath;
    }
    return '';
  }

  private async runFilesystemOrphanMigration(): Promise<OnlineArchiveMigrationItem[]> {
    const candidates = await this.collectFilesystemOrphanCandidates();
    const items: OnlineArchiveMigrationItem[] = [];

    for (let i = 0; i < candidates.length; i++) {
      const item = await this.migrateFilesystemOrphanCandidate(candidates[i]);
      items.push(item);
    }

    logger.info(TAG, `孤儿本地缓存扫描完成: candidates=${candidates.length}, items=${items.length}`);
    return items;
  }

  private async collectFilesystemOrphanCandidates(): Promise<FilesystemOrphanCandidate[]> {
    const context = this.requireContext();
    const candidates: FilesystemOrphanCandidate[] = [];
    const seenDirectories: string[] = [];

    if (this.downloadDirManager.isReady()) {
      const publicMangaRoot = `${this.normalizeDirectoryPath(this.downloadDirManager.getPath())}/manga`;
      await this.collectArchiveStyleCandidates(
        publicMangaRoot,
        'public_archive',
        true,
        candidates,
        seenDirectories
      );
      await this.collectRawIdStyleCandidates(
        publicMangaRoot,
        'public_legacy',
        true,
        candidates,
        seenDirectories
      );
    }

    const privateArchiveRoot = `${this.normalizeDirectoryPath(context.filesDir)}/downloads/online_archive`;
    await this.collectArchiveStyleCandidates(
      privateArchiveRoot,
      'private_archive',
      false,
      candidates,
      seenDirectories
    );

    const privateDownloadRoot = `${this.normalizeDirectoryPath(context.filesDir)}/downloads`;
    await this.collectRawIdStyleCandidates(
      privateDownloadRoot,
      'private_legacy',
      false,
      candidates,
      seenDirectories
    );

    const permanentCacheRoot = `${this.normalizeDirectoryPath(context.filesDir)}/permanent_cache`;
    await this.collectPermanentCacheCandidates(
      permanentCacheRoot,
      candidates,
      seenDirectories
    );

    return candidates;
  }

  private async collectArchiveStyleCandidates(
    rootPath: string,
    rootType: string,
    preferPublicDownloadDir: boolean,
    candidates: FilesystemOrphanCandidate[],
    seenDirectories: string[]
  ): Promise<void> {
    if (!this.isDirectoryPath(rootPath)) {
      return;
    }

    const imageDirectories = this.scanDirectoriesWithDirectImages(rootPath);
    for (let i = 0; i < imageDirectories.length; i++) {
      const imageDirectory = imageDirectories[i];
      if (this.hasSeenDirectory(imageDirectory.directoryPath, seenDirectories)) {
        continue;
      }

      const relativePath = this.getRelativePath(rootPath, imageDirectory.directoryPath);
      const parts = this.splitPathParts(relativePath);
      if (parts.length < 3) {
        continue;
      }

      const sourceSegment = parts[0];
      const mangaTitle = parts[1];
      const chapterTitle = parts[2];
      const sourceRecord = await this.querySourceRecordByNameOrPkg(sourceSegment);
      const sourceId = sourceRecord ? sourceRecord.id : '0';
      const sourceName = sourceRecord ? sourceRecord.name : sourceSegment;
      const sourcePkg = sourceRecord ? sourceRecord.pkg : '';
      const mangaExternalId = `filesystem:${rootType}:${sourceId}:${mangaTitle}`;
      const chapterExternalId = `${mangaExternalId}:${chapterTitle}`;
      const candidate: FilesystemOrphanCandidate = {
        scanKey: `${rootType}:${imageDirectory.directoryPath}`,
        rootType: rootType,
        directoryPath: imageDirectory.directoryPath,
        sourceId: sourceId,
        sourceName: sourceName,
        sourcePkg: sourcePkg,
        mangaExternalId: mangaExternalId,
        chapterExternalId: chapterExternalId,
        preferredMangaId: this.buildStableRecoveredId('recovered_manga', mangaExternalId),
        preferredChapterId: this.buildStableRecoveredId('recovered_chapter', chapterExternalId),
        mangaTitle: mangaTitle,
        chapterTitle: chapterTitle,
        chapterUrl: imageDirectory.directoryPath,
        chapterNumber: this.extractStableSortNumber(chapterTitle),
        pageFiles: this.buildOrphanPageFiles(imageDirectory.imageFiles),
        preferPublicDownloadDir: preferPublicDownloadDir,
        isPrivate: false,
        isNSFW: sourceRecord ? sourceRecord.isNSFW === 1 : false
      };
      candidates.push(candidate);
      seenDirectories.push(this.normalizeDirectoryPath(imageDirectory.directoryPath));
    }
  }

  private async collectRawIdStyleCandidates(
    rootPath: string,
    rootType: string,
    preferPublicDownloadDir: boolean,
    candidates: FilesystemOrphanCandidate[],
    seenDirectories: string[]
  ): Promise<void> {
    if (!this.isDirectoryPath(rootPath)) {
      return;
    }

    const imageDirectories = this.scanDirectoriesWithDirectImages(rootPath);
    for (let i = 0; i < imageDirectories.length; i++) {
      const imageDirectory = imageDirectories[i];
      if (this.hasSeenDirectory(imageDirectory.directoryPath, seenDirectories)) {
        continue;
      }

      const relativePath = this.getRelativePath(rootPath, imageDirectory.directoryPath);
      const parts = this.splitPathParts(relativePath);
      if (parts.length < 2 || parts[0] === 'online_archive') {
        continue;
      }

      const mangaId = parts[0];
      const chapterId = parts[1];
      const candidate: FilesystemOrphanCandidate = {
        scanKey: `${rootType}:${imageDirectory.directoryPath}`,
        rootType: rootType,
        directoryPath: imageDirectory.directoryPath,
        sourceId: '0',
        sourceName: 'unknown_source',
        sourcePkg: '',
        mangaExternalId: mangaId,
        chapterExternalId: chapterId,
        preferredMangaId: this.sanitizeRecoveredId(mangaId, 'recovered_manga'),
        preferredChapterId: this.buildStableRecoveredId('recovered_chapter', `${rootType}:${mangaId}:${chapterId}`),
        mangaTitle: mangaId,
        chapterTitle: chapterId,
        chapterUrl: imageDirectory.directoryPath,
        chapterNumber: this.extractStableSortNumber(chapterId),
        pageFiles: this.buildOrphanPageFiles(imageDirectory.imageFiles),
        preferPublicDownloadDir: preferPublicDownloadDir,
        isPrivate: false,
        isNSFW: false
      };
      candidates.push(candidate);
      seenDirectories.push(this.normalizeDirectoryPath(imageDirectory.directoryPath));
    }
  }

  private async collectPermanentCacheCandidates(
    rootPath: string,
    candidates: FilesystemOrphanCandidate[],
    seenDirectories: string[]
  ): Promise<void> {
    if (!this.isDirectoryPath(rootPath)) {
      return;
    }

    const imageDirectories = this.scanDirectoriesWithDirectImages(rootPath);
    for (let i = 0; i < imageDirectories.length; i++) {
      const imageDirectory = imageDirectories[i];
      if (this.hasSeenDirectory(imageDirectory.directoryPath, seenDirectories)) {
        continue;
      }

      const relativePath = this.getRelativePath(rootPath, imageDirectory.directoryPath);
      const parts = this.splitPathParts(relativePath);
      if (parts.length < 3) {
        continue;
      }
      if (!parts[0].startsWith('source_') || !parts[1].startsWith('manga_') || !parts[2].startsWith('chapter_')) {
        continue;
      }

      const sourceId = parts[0].substring(7);
      const mangaId = parts[1].substring(6);
      const chapterId = parts[2].substring(8);
      if (sourceId.length === 0 || mangaId.length === 0 || chapterId.length === 0) {
        continue;
      }

      const sourceRecord = await this.querySourceRecordById(sourceId);
      const sourceName = sourceRecord ? sourceRecord.name : `source_${sourceId}`;
      const sourcePkg = sourceRecord ? sourceRecord.pkg : '';
      const candidate: FilesystemOrphanCandidate = {
        scanKey: `permanent_cache:${imageDirectory.directoryPath}`,
        rootType: 'permanent_cache',
        directoryPath: imageDirectory.directoryPath,
        sourceId: sourceId,
        sourceName: sourceName,
        sourcePkg: sourcePkg,
        mangaExternalId: mangaId,
        chapterExternalId: chapterId,
        preferredMangaId: this.sanitizeRecoveredId(mangaId, 'recovered_manga'),
        preferredChapterId: this.sanitizeRecoveredId(chapterId, 'recovered_chapter'),
        mangaTitle: mangaId,
        chapterTitle: chapterId,
        chapterUrl: imageDirectory.directoryPath,
        chapterNumber: this.extractStableSortNumber(chapterId),
        pageFiles: this.buildOrphanPageFiles(imageDirectory.imageFiles),
        preferPublicDownloadDir: false,
        isPrivate: false,
        isNSFW: sourceRecord ? sourceRecord.isNSFW === 1 : false
      };
      candidates.push(candidate);
      seenDirectories.push(this.normalizeDirectoryPath(imageDirectory.directoryPath));
    }
  }

  private async migrateFilesystemOrphanCandidate(candidate: FilesystemOrphanCandidate): Promise<OnlineArchiveMigrationItem> {
    const item: OnlineArchiveMigrationItem = {
      chapterId: candidate.preferredChapterId,
      mangaTitle: candidate.mangaTitle,
      chapterTitle: candidate.chapterTitle,
      sourceName: candidate.sourceName,
      status: OnlineArchiveMigrationStatus.FAILED,
      message: '',
      archivePath: '',
      pageCount: candidate.pageFiles.length,
      archiveSize: 0,
      migratedTime: Date.now()
    };

    try {
      if (candidate.pageFiles.length === 0) {
        item.status = OnlineArchiveMigrationStatus.SKIPPED;
        item.message = '本地目录未找到图片';
        return item;
      }

      const existingChapter = await this.findExistingOrphanChapter(candidate);
      if (existingChapter && this.isCbzPath(existingChapter.downloadPath) && this.pathExists(existingChapter.downloadPath)) {
        item.chapterId = existingChapter.chapterId;
        item.status = OnlineArchiveMigrationStatus.SKIPPED;
        item.message = '章节已存在有效CBZ归档';
        item.archivePath = existingChapter.downloadPath;
        item.archiveSize = this.getFileSize(existingChapter.downloadPath);
        item.pageCount = existingChapter.pageCount > 0 ? existingChapter.pageCount : candidate.pageFiles.length;
        item.migratedTime = Date.now();
        return item;
      }

      const comicId = existingChapter
        ? existingChapter.comicId
        : await this.resolveExistingOrphanComicId(candidate);
      const chapterId = existingChapter ? existingChapter.chapterId : candidate.preferredChapterId;
      item.chapterId = chapterId;

      await this.upsertRecoveredOnlineRecords(
        candidate,
        comicId,
        chapterId,
        candidate.directoryPath,
        candidate.pageFiles.length
      );

      const metadata = this.buildMetadataFromFilesystemCandidate(candidate, comicId, chapterId);
      const createRequest: OnlineArchiveCreateRequest = {
        sourceName: candidate.sourceName,
        sourcePkg: candidate.sourcePkg,
        mangaTitle: candidate.mangaTitle,
        chapterTitle: candidate.chapterTitle,
        mangaId: comicId,
        chapterId: chapterId,
        pageFiles: candidate.pageFiles,
        metadata: metadata,
        preferPublicDownloadDir: candidate.preferPublicDownloadDir
      };
      const result = await this.createArchiveFromPageFiles(createRequest);

      await this.databaseManager.executeSql(
        'UPDATE online_chapter SET isDownloaded = 1, downloadPath = ?, pageCount = ?, updateTime = ? WHERE id = ?',
        [result.archivePath, result.pageCount, Date.now(), chapterId]
      );
      await this.databaseManager.executeSql(
        'UPDATE online_page SET isDownloaded = 1 WHERE chapterId = ?',
        [chapterId]
      );
      await this.syncOnlineChapterArchiveStatus(chapterId, 'orphan_migration_created_archive_state_sync');

      item.status = OnlineArchiveMigrationStatus.MIGRATED;
      item.message = `已从本地目录恢复数据库记录并迁移CBZ: ${candidate.rootType}`;
      item.archivePath = result.archivePath;
      item.pageCount = result.pageCount;
      item.archiveSize = result.archiveSize;
      item.migratedTime = Date.now();
      return item;
    } catch (error) {
      item.status = OnlineArchiveMigrationStatus.FAILED;
      item.message = String(error);
      item.migratedTime = Date.now();
      logger.warn(TAG, `孤儿缓存迁移失败: dir=${candidate.directoryPath}, error=${String(error)}`);
      return item;
    }
  }

  private async upsertRecoveredOnlineRecords(
    candidate: FilesystemOrphanCandidate,
    comicId: string,
    chapterId: string,
    downloadPath: string,
    pageCount: number
  ): Promise<void> {
    const now = Date.now();
    await this.databaseManager.beginTransaction();
    try {
      await this.databaseManager.executeSql(
        `INSERT OR IGNORE INTO online_comic_info
         (id, sourceId, externalId, title, author, description, coverUrl, tags, rating, lastUpdateTime, addTime, createTime, updateTime, sourceName, sourcePkg, isPrivate, isNSFW)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          comicId,
          candidate.sourceId,
          candidate.mangaExternalId,
          candidate.mangaTitle,
          '',
          '从本地缓存目录恢复',
          '',
          '',
          0,
          now,
          now,
          now,
          now,
          candidate.sourceName,
          candidate.sourcePkg,
          candidate.isPrivate ? 1 : 0,
          candidate.isNSFW ? 1 : 0
        ]
      );
      await this.databaseManager.executeSql(
        'UPDATE online_comic_info SET title = ?, sourceName = ?, sourcePkg = ?, isPrivate = ?, isNSFW = ?, lastUpdateTime = ?, updateTime = ? WHERE id = ?',
        [
          candidate.mangaTitle,
          candidate.sourceName,
          candidate.sourcePkg,
          candidate.isPrivate ? 1 : 0,
          candidate.isNSFW ? 1 : 0,
          now,
          now,
          comicId
        ]
      );

      await this.databaseManager.executeSql(
        `INSERT OR IGNORE INTO online_chapter
         (id, comicId, externalId, title, chapterNumber, url, pageCount, publishTime, addTime, createTime, updateTime, isDownloaded, downloadPath, \`index\`)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          chapterId,
          comicId,
          candidate.chapterExternalId,
          candidate.chapterTitle,
          candidate.chapterNumber,
          candidate.chapterUrl,
          pageCount,
          0,
          now,
          now,
          now,
          1,
          downloadPath,
          candidate.chapterNumber
        ]
      );
      await this.databaseManager.executeSql(
        'UPDATE online_chapter SET title = ?, pageCount = ?, url = ?, isDownloaded = 1, downloadPath = ?, updateTime = ?, `index` = ? WHERE id = ?',
        [
          candidate.chapterTitle,
          pageCount,
          candidate.chapterUrl,
          downloadPath,
          now,
          candidate.chapterNumber,
          chapterId
        ]
      );

      await this.databaseManager.executeSql('DELETE FROM online_page WHERE chapterId = ?', [chapterId]);
      for (let i = 0; i < candidate.pageFiles.length; i++) {
        const page = candidate.pageFiles[i];
        await this.databaseManager.executeSql(
          `INSERT INTO online_page
           (id, chapterId, pageNumber, imageUrl, requestHeaders, localPath, width, height, fileSize, isDownloaded, createTime)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            generateDbId('online_page'),
            chapterId,
            page.pageIndex,
            page.imageUrl,
            '',
            page.sourcePath,
            page.width,
            page.height,
            page.fileSize,
            1,
            now
          ]
        );
      }

      await this.databaseManager.commit();
      logger.info(TAG, `已恢复本地缓存数据库记录: comicId=${comicId}, chapterId=${chapterId}, pages=${pageCount}`);
    } catch (error) {
      await this.databaseManager.rollBack();
      throw error as Error;
    }
  }

  private async findExistingOrphanChapter(candidate: FilesystemOrphanCandidate): Promise<ExistingOrphanChapterRecord | null> {
    const sql = `
      SELECT oci.id as comicId,
             oc.id as chapterId,
             oc.pageCount,
             oc.downloadPath,
             (SELECT COUNT(*) FROM online_page op WHERE op.chapterId = oc.id) as chapterCount
      FROM online_comic_info oci
      INNER JOIN online_chapter oc ON oc.comicId = oci.id
      WHERE (
        (oci.sourceId = ? AND oci.externalId = ?)
        OR oci.id = ?
        OR (oci.sourceId = ? AND oci.title = ?)
        OR (? != '' AND oci.sourceName = ? AND oci.title = ?)
        OR (? != '' AND oci.sourcePkg = ? AND oci.title = ?)
      )
      AND (
        oc.externalId = ?
        OR oc.id = ?
        OR oc.title = ?
      )
      ORDER BY oc.updateTime DESC
      LIMIT 1
    `;
    const records = await this.databaseManager.querySql(sql, [
      candidate.sourceId,
      candidate.mangaExternalId,
      candidate.preferredMangaId,
      candidate.sourceId,
      candidate.mangaTitle,
      candidate.sourceName,
      candidate.sourceName,
      candidate.mangaTitle,
      candidate.sourcePkg,
      candidate.sourcePkg,
      candidate.mangaTitle,
      candidate.chapterExternalId,
      candidate.preferredChapterId,
      candidate.chapterTitle
    ]);
    if (records.length === 0) {
      return null;
    }
    const record = records[0] as GenericQueryRecord;
    const existing: ExistingOrphanChapterRecord = {
      comicId: String(record.comicId || ''),
      chapterId: String(record.chapterId || ''),
      pageCount: Number(record.pageCount || 0),
      pageRecordCount: Number(record.chapterCount || 0),
      downloadPath: String(record.downloadPath || '')
    };
    if (existing.comicId.length === 0 || existing.chapterId.length === 0) {
      return null;
    }
    return existing;
  }

  private async resolveExistingOrphanComicId(candidate: FilesystemOrphanCandidate): Promise<string> {
    const sql = `
      SELECT id
      FROM online_comic_info
      WHERE id = ?
        OR (sourceId = ? AND externalId = ?)
        OR (sourceId = ? AND title = ?)
        OR (? != '' AND sourceName = ? AND title = ?)
        OR (? != '' AND sourcePkg = ? AND title = ?)
      ORDER BY updateTime DESC
      LIMIT 1
    `;
    const records = await this.databaseManager.querySql(sql, [
      candidate.preferredMangaId,
      candidate.sourceId,
      candidate.mangaExternalId,
      candidate.sourceId,
      candidate.mangaTitle,
      candidate.sourceName,
      candidate.sourceName,
      candidate.mangaTitle,
      candidate.sourcePkg,
      candidate.sourcePkg,
      candidate.mangaTitle
    ]);
    if (records.length > 0) {
      const record = records[0] as GenericQueryRecord;
      const existingId = String(record.id || '');
      if (existingId.length > 0) {
        return existingId;
      }
    }
    return candidate.preferredMangaId;
  }

  private async querySourceRecordByNameOrPkg(sourceSegment: string): Promise<OnlineArchiveSourceRecord | null> {
    const records = await this.databaseManager.querySql(
      'SELECT id, name, pkg, isNSFW FROM comic_source WHERE name = ? OR pkg = ? LIMIT 1',
      [sourceSegment, sourceSegment]
    );
    const exactRecord = this.convertSourceRecord(records as GenericQueryRecord[]);
    if (exactRecord) {
      return exactRecord;
    }

    const allRecords = await this.databaseManager.querySql(
      'SELECT id, name, pkg, isNSFW FROM comic_source',
      []
    );
    for (let i = 0; i < allRecords.length; i++) {
      const source = this.convertSingleSourceRecord(allRecords[i] as GenericQueryRecord);
      if (!source) {
        continue;
      }
      const safeName = this.sanitizePathSegment(source.name);
      const safePkg = this.sanitizePathSegment(source.pkg);
      if (safeName === sourceSegment || safePkg === sourceSegment) {
        return source;
      }
    }
    return null;
  }

  private async querySourceRecordById(sourceId: string): Promise<OnlineArchiveSourceRecord | null> {
    const records = await this.databaseManager.querySql(
      'SELECT id, name, pkg, isNSFW FROM comic_source WHERE id = ? LIMIT 1',
      [sourceId]
    );
    return this.convertSourceRecord(records as GenericQueryRecord[]);
  }

  private convertSourceRecord(records: GenericQueryRecord[]): OnlineArchiveSourceRecord | null {
    if (records.length === 0) {
      return null;
    }
    const record = records[0] as GenericQueryRecord;
    return this.convertSingleSourceRecord(record);
  }

  private convertSingleSourceRecord(record: GenericQueryRecord): OnlineArchiveSourceRecord | null {
    const id = String(record.id || '');
    if (id.length === 0) {
      return null;
    }
    const source: OnlineArchiveSourceRecord = {
      id: id,
      name: String(record.name || `source_${id}`),
      pkg: String(record.pkg || ''),
      isNSFW: Number(record.isNSFW || 0)
    };
    return source;
  }

  private buildMetadataFromFilesystemCandidate(
    candidate: FilesystemOrphanCandidate,
    mangaId: string,
    chapterId: string
  ): OnlineArchiveMetadata {
    return {
      sourceId: candidate.sourceId,
      sourceName: candidate.sourceName,
      sourcePkg: candidate.sourcePkg,
      mangaId: mangaId,
      mangaTitle: candidate.mangaTitle,
      chapterId: chapterId,
      chapterTitle: candidate.chapterTitle,
      chapterUrl: candidate.chapterUrl,
      author: '',
      description: '从本地缓存目录恢复',
      coverUrl: '',
      tags: [],
      lastUpdateTime: Date.now(),
      isPrivate: candidate.isPrivate,
      isNSFW: candidate.isNSFW
    };
  }

  private buildOrphanPageFiles(imageFiles: string[]): OnlineArchivePageFile[] {
    const pageFiles: OnlineArchivePageFile[] = [];
    for (let i = 0; i < imageFiles.length; i++) {
      const imagePath = imageFiles[i];
      const pageFile: OnlineArchivePageFile = {
        pageIndex: i,
        imageUrl: imagePath,
        sourcePath: imagePath,
        width: 0,
        height: 0,
        fileSize: this.getFileSize(imagePath)
      };
      pageFiles.push(pageFile);
    }
    return pageFiles;
  }

  private scanDirectoriesWithDirectImages(rootPath: string): FilesystemImageDirectory[] {
    const directories: FilesystemImageDirectory[] = [];
    this.scanDirectoriesWithDirectImagesRecursive(
      this.normalizeDirectoryPath(rootPath),
      directories
    );
    return directories;
  }

  private scanDirectoriesWithDirectImagesRecursive(
    dirPath: string,
    directories: FilesystemImageDirectory[]
  ): void {
    if (!this.isDirectoryPath(dirPath)) {
      return;
    }

    try {
      const entries = SafeFileUtils.listFileSync(dirPath);
      const directImageFiles: string[] = [];
      const childDirectories: string[] = [];
      for (let i = 0; i < entries.length; i++) {
        const fullPath = `${dirPath}/${entries[i]}`;
        const stat = SafeFileUtils.statSync(fullPath);
        if (stat.isDirectory()) {
          childDirectories.push(fullPath);
        } else if (this.isImagePath(fullPath)) {
          directImageFiles.push(fullPath);
        }
      }

      if (directImageFiles.length > 0) {
        directImageFiles.sort((left: string, right: string) => {
          return this.extractSortNumber(left) - this.extractSortNumber(right);
        });
        const imageDirectory: FilesystemImageDirectory = {
          directoryPath: dirPath,
          imageFiles: directImageFiles
        };
        directories.push(imageDirectory);
      }

      for (let i = 0; i < childDirectories.length; i++) {
        this.scanDirectoriesWithDirectImagesRecursive(childDirectories[i], directories);
      }
    } catch (error) {
      logger.warn(TAG, `扫描本地缓存目录失败: ${dirPath}, ${String(error)}`);
    }
  }

  private hasSeenDirectory(directoryPath: string, seenDirectories: string[]): boolean {
    return seenDirectories.includes(this.normalizeDirectoryPath(directoryPath));
  }

  private getRelativePath(rootPath: string, childPath: string): string {
    const normalizedRoot = this.normalizeDirectoryPath(rootPath);
    const normalizedChild = this.normalizeDirectoryPath(childPath);
    const prefix = `${normalizedRoot}/`;
    if (normalizedChild.startsWith(prefix)) {
      return normalizedChild.substring(prefix.length);
    }
    if (normalizedChild === normalizedRoot) {
      return '';
    }
    return normalizedChild;
  }

  private splitPathParts(path: string): string[] {
    const rawParts = this.normalizeDirectoryPath(path).split('/');
    const parts: string[] = [];
    for (let i = 0; i < rawParts.length; i++) {
      const part = rawParts[i].trim();
      if (part.length > 0) {
        parts.push(part);
      }
    }
    return parts;
  }

  private normalizeDirectoryPath(path: string): string {
    let normalized = this.normalizeFileSystemPath(path).replace(/\\/g, '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  private getParentDirectoryPath(path: string): string {
    const normalized = this.normalizeDirectoryPath(path);
    const slashIndex = normalized.lastIndexOf('/');
    if (slashIndex <= 0) {
      return '';
    }
    return normalized.substring(0, slashIndex);
  }

  private isDirectoryPath(path: string): boolean {
    try {
      if (!this.pathExists(path)) {
        return false;
      }
      const stat = SafeFileUtils.statSync(path);
      return stat.isDirectory();
    } catch (_error) {
      return false;
    }
  }

  private sanitizeRecoveredId(value: string, fallbackPrefix: string): string {
    const sanitized = value.trim().replace(/[^a-zA-Z0-9_-]/g, '_');
    if (sanitized.length > 0) {
      return sanitized.substring(0, 160);
    }
    return generateDbId(fallbackPrefix);
  }

  private buildStableRecoveredId(prefix: string, key: string): string {
    let hash = 0;
    for (let i = 0; i < key.length; i++) {
      hash = (hash * 31 + key.charCodeAt(i)) % 2147483647;
    }
    const safeKey = key.replace(/[^a-zA-Z0-9_-]/g, '_').substring(0, 80);
    return `${prefix}_${hash}_${safeKey}`;
  }

  private extractStableSortNumber(value: string): number {
    const sortNumber = this.extractSortNumber(value);
    if (sortNumber === Number.MAX_SAFE_INTEGER) {
      return 0;
    }
    return sortNumber;
  }

  private normalizeFileSystemPath(path: string): string {
    const trimmed = path.trim();
    if (trimmed.length === 0) {
      return '';
    }
    if (trimmed.startsWith('file://')) {
      return trimmed.substring(7);
    }
    if (trimmed.startsWith('/')) {
      return trimmed;
    }
    if (trimmed.startsWith('storage/') || trimmed.startsWith('data/')) {
      return `/${trimmed}`;
    }
    return trimmed;
  }

  private buildMetadataFromComic(comic: OnlineComicInfo, chapter: OnlineChapterInfo): OnlineArchiveMetadata {
    return {
      sourceId: comic.sourceId,
      sourceName: comic.sourceName,
      sourcePkg: comic.sourcePkg,
      mangaId: comic.id,
      mangaTitle: comic.title,
      chapterId: chapter.id,
      chapterTitle: chapter.title,
      chapterUrl: chapter.url,
      author: comic.author,
      description: comic.description,
      coverUrl: comic.coverUrl,
      tags: comic.tags,
      lastUpdateTime: comic.lastUpdateTime,
      isPrivate: comic.isPrivate === 1,
      isNSFW: comic.isNSFW === 1
    };
  }

  private buildComicInfoXml(metadata: OnlineArchiveMetadata, pageCount: number, failedPageIndexes?: number[]): string {
    const mangaMetadata: MangaMetadata = {
      title: metadata.chapterTitle,
      series: metadata.mangaTitle,
      author: metadata.author,
      description: metadata.description,
      tags: metadata.tags,
      coverUrl: metadata.coverUrl,
      sourceId: metadata.sourcePkg.length > 0 ? metadata.sourcePkg : metadata.sourceId,
      sourceName: metadata.sourceName,
      url: metadata.chapterUrl,
      lastUpdateTime: metadata.lastUpdateTime,
      isPrivate: metadata.isPrivate,
      isNSFW: metadata.isNSFW
    };
    const baseXml = MetadataXmlGenerator.generateComicInfoXml(mangaMetadata);
    const extraLines: string[] = [];
    extraLines.push(`  <Number>${this.escapeXml(metadata.chapterTitle)}</Number>`);
    extraLines.push(`  <PageCount>${pageCount}</PageCount>`);
    extraLines.push(`  <MangaId>${this.escapeXml(metadata.mangaId)}</MangaId>`);
    extraLines.push(`  <ChapterId>${this.escapeXml(metadata.chapterId)}</ChapterId>`);
    extraLines.push(`  <SourcePkg>${this.escapeXml(metadata.sourcePkg)}</SourcePkg>`);
    if (failedPageIndexes && failedPageIndexes.length > 0) {
      extraLines.push(`  <IsPartialArchive>true</IsPartialArchive>`);
      extraLines.push(`  <FailedPages>${failedPageIndexes.join(',')}</FailedPages>`);
      extraLines.push(`  <DownloadedPageCount>${pageCount - failedPageIndexes.length}</DownloadedPageCount>`);
    }
    return baseXml.replace('</ComicInfo>', `${extraLines.join('\n')}\n</ComicInfo>`);
  }

  private resolveArchivePath(request: OnlineArchiveCreateRequest): string {
    const sourceSegment = request.sourceName.length > 0 ? request.sourceName : request.sourcePkg;
    const archiveDir = request.preferPublicDownloadDir && this.downloadDirManager.isReady()
      ? this.downloadDirManager.getMangaArchiveDirectoryPath(sourceSegment, request.mangaTitle, request.chapterTitle)
      : this.getPrivateArchiveDirectory(sourceSegment, request.mangaTitle, request.chapterTitle);
    const fileName = `${this.sanitizePathSegment(request.chapterTitle.length > 0 ? request.chapterTitle : request.chapterId)}.cbz`;
    return `${archiveDir}/${fileName}`;
  }

  private buildArchivePathRequest(comic: OnlineComicInfo, chapter: OnlineChapterInfo): OnlineMangaArchivePathRequest {
    const request: OnlineMangaArchivePathRequest = {
      sourceId: comic.sourceId,
      sourceName: comic.sourceName,
      sourcePkg: comic.sourcePkg,
      mangaTitle: comic.title,
      chapterTitle: chapter.title,
      chapterId: chapter.id,
      chapterNumber: chapter.chapterNumber > 0 ? String(chapter.chapterNumber) : '',
      externalChapterId: chapter.externalId,
      storedArchivePath: chapter.downloadPath || ''
    };
    return request;
  }

  private resolveArchivePathFromStoredDownloadPath(rawDownloadPath: string, chapter: OnlineChapterInfo): string {
    const storedPath = this.normalizeFileSystemPath(rawDownloadPath);
    if (storedPath.length <= 0) {
      return '';
    }

    if (this.isCbzPath(storedPath)) {
      if (this.pathExists(storedPath)) {
        return storedPath;
      }
      return this.recoverArchiveTempFile(storedPath);
    }

    if (this.isDirectoryPath(storedPath)) {
      const archiveInDirectory = this.findCbzArchiveInDirectory(storedPath);
      if (archiveInDirectory.length > 0) {
        logger.info(TAG, `通过online_chapter.downloadPath目录发现CBZ: chapter=${chapter.title}, path=${archiveInDirectory}`);
        return archiveInDirectory;
      }
      const fileNames = this.resolveArchiveLookupFileNames(chapter);
      for (let i = 0; i < fileNames.length; i++) {
        const archivePath = `${this.normalizeDirectoryPath(storedPath)}/${fileNames[i]}`;
        if (this.pathExists(archivePath)) {
          return archivePath;
        }
        const recoveredArchivePath = this.recoverArchiveTempFile(archivePath);
        if (recoveredArchivePath.length > 0) {
          return recoveredArchivePath;
        }
      }
    }

    const parentPath = this.getParentDirectoryPath(storedPath);
    if (parentPath.length > 0 && this.isDirectoryPath(parentPath)) {
      const archiveInParent = this.findCbzArchiveInDirectory(parentPath);
      if (archiveInParent.length > 0) {
        logger.info(TAG, `通过online_chapter.downloadPath父目录发现CBZ: chapter=${chapter.title}, path=${archiveInParent}`);
        return archiveInParent;
      }
    }

    return '';
  }

  private resolveArchiveLookup(comic: OnlineComicInfo, chapter: OnlineChapterInfo): OnlineMangaArchiveLookupResult {
    const request = this.buildArchivePathRequest(comic, chapter);
    return this.downloadDirManager.resolveExistingOnlineMangaArchive(request);
  }

  private resolveArchiveLookupFileNames(chapter: OnlineChapterInfo): string[] {
    const fileNames: string[] = [];
    this.appendArchiveLookupFileName(fileNames, chapter.title);
    this.appendArchiveLookupFileName(fileNames, chapter.externalId);
    this.appendArchiveLookupFileName(fileNames, chapter.id);
    if (chapter.chapterNumber > 0) {
      this.appendArchiveLookupFileName(fileNames, String(chapter.chapterNumber));
    }
    return fileNames;
  }

  private appendArchiveLookupFileName(fileNames: string[], rawName: string): void {
    const trimmed = rawName.trim();
    if (trimmed.length <= 0) {
      return;
    }
    const fileName = `${this.sanitizePathSegment(trimmed)}.cbz`;
    for (let i = 0; i < fileNames.length; i++) {
      if (fileNames[i] === fileName) {
        return;
      }
    }
    fileNames.push(fileName);
  }

  private deduplicatePaths(paths: string[]): string[] {
    const result: string[] = [];
    for (let i = 0; i < paths.length; i++) {
      const currentPath = paths[i];
      let exists = false;
      for (let j = 0; j < result.length; j++) {
        if (result[j] === currentPath) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        result.push(currentPath);
      }
    }
    return result;
  }

  private async resolveExistingArchiveForChapter(comic: OnlineComicInfo, chapter: OnlineChapterInfo): Promise<string> {
    const lookup = this.resolveArchiveLookup(comic, chapter);
    if (lookup.archivePath.length > 0) {
      logger.info(TAG, `统一Download目录管理器命中在线漫画CBZ: chapter=${chapter.title}, matchedBy=${lookup.matchedBy}, path=${lookup.archivePath}`);
      return lookup.archivePath;
    }
    return '';
  }

  private async logArchiveLookupMiss(comic: OnlineComicInfo, chapter: OnlineChapterInfo, reason: string): Promise<void> {
    const normalizedReason = reason.length > 0 ? reason : 'unspecified';
    const logKey = `${normalizedReason}:${chapter.id}`;
    if (this.archiveLookupMissLogKeys.has(logKey)) {
      return;
    }
    if (normalizedReason === 'cache_status' && this.archiveLookupMissLogKeys.size >= 12) {
      return;
    }
    this.archiveLookupMissLogKeys.add(logKey);

    const lookup = this.resolveArchiveLookup(comic, chapter);
    const candidates = lookup.candidates;
    const samplePaths: string[] = [];
    for (let i = 0; i < candidates.length && samplePaths.length < 8; i++) {
      samplePaths.push(candidates[i]);
    }

    const downloadReady = this.downloadDirManager.isReady();
    const downloadRoot = downloadReady ? this.normalizeDirectoryPath(this.downloadDirManager.getPath()) : '';
    const contextRoot = this.context !== null ? this.normalizeDirectoryPath(this.context.filesDir) : '';
    logger.warn(
      TAG,
      `未发现在线章节CBZ归档: reason=${normalizedReason}, manga=${comic.title}, chapter=${chapter.title}, chapterId=${chapter.id}, external=${chapter.externalId}, storedPath=${chapter.downloadPath || ''}, downloadReady=${downloadReady}, downloadRoot=${downloadRoot}, filesRoot=${contextRoot}, candidates=${candidates.length}, samples=${samplePaths.join(' | ')}`
    );
  }

  private findCbzArchiveInDirectory(directoryPath: string): string {
    const normalizedDirectory = this.normalizeDirectoryPath(directoryPath);
    if (!this.isDirectoryPath(normalizedDirectory)) {
      return '';
    }

    try {
      const entries = SafeFileUtils.listFileSync(normalizedDirectory);
      entries.sort((left: string, right: string) => {
        return left.localeCompare(right);
      });
      for (let i = 0; i < entries.length; i++) {
        const fullPath = `${normalizedDirectory}/${entries[i]}`;
        if (!this.isCbzPath(fullPath)) {
          continue;
        }
        const stat = SafeFileUtils.statSync(fullPath);
        if (!stat.isDirectory()) {
          return fullPath;
        }
      }
    } catch (error) {
      logger.warn(TAG, `扫描章节CBZ目录失败: ${normalizedDirectory}, ${String(error)}`);
    }
    return '';
  }

  private async resolveKnownOnlineChapterPageCount(chapterId: string): Promise<number> {
    try {
      const rows = await this.databaseManager.querySql(
        'SELECT (SELECT COUNT(*) FROM online_page WHERE chapterId = ?) AS pageCount, (SELECT pageCount FROM online_chapter WHERE id = ?) AS chapterPageCount',
        [chapterId, chapterId]
      );
      if (rows.length <= 0) {
        return 0;
      }
      const row = rows[0] as GenericQueryRecord;
      const pageCount = Number(row.pageCount || 0);
      const chapterPageCount = Number(row.chapterPageCount || 0);
      const safePageCount = this.isUsableNumber(pageCount) && pageCount > 0 ? Math.floor(pageCount) : 0;
      const safeChapterPageCount = this.isUsableNumber(chapterPageCount) && chapterPageCount > 0 ? Math.floor(chapterPageCount) : 0;
      return Math.max(safePageCount, safeChapterPageCount);
    } catch (error) {
      logger.warn(TAG, `查询在线章节页表数量失败: chapter=${chapterId}, ${String(error)}`);
      return 0;
    }
  }

  private inspectArchiveCacheState(
    archivePath: string,
    chapter: OnlineChapterInfo,
    knownPageCount: number
  ): OnlineArchiveCacheState {
    const readInfo = this.readArchiveEntryInfo(archivePath);
    const imageEntryCount = this.countArchiveImageEntries(readInfo.entryNames);
    const hasReadableEntries = readInfo.entryNames.length > 0;
    const hasComicInfo = readInfo.comicInfoXml.length > 0;

    const xmlPageCount = hasComicInfo
      ? this.parsePositiveIntegerXmlField(readInfo.comicInfoXml, 'PageCount')
      : 0;
    let failedPageIndexes = hasComicInfo
      ? this.parseFailedPageIndexes(readInfo.comicInfoXml)
      : [];
    const downloadedPageCountFromXml = hasComicInfo
      ? this.parsePositiveIntegerXmlField(readInfo.comicInfoXml, 'DownloadedPageCount')
      : 0;
    let totalPageCount = Math.max(xmlPageCount, chapter.pageCount || 0, knownPageCount, imageEntryCount);
    failedPageIndexes = this.normalizeFailedPageIndexesForTotal(failedPageIndexes, totalPageCount);
    let isPartialArchive = hasComicInfo && (
      this.parseBooleanXmlField(readInfo.comicInfoXml, 'IsPartialArchive') ||
        failedPageIndexes.length > 0
    );

    if (!hasReadableEntries) {
      isPartialArchive = true;
    }
    if (totalPageCount > 0 && imageEntryCount < totalPageCount) {
      isPartialArchive = true;
    }

    let downloadedPageCount = 0;
    if (isPartialArchive) {
      if (downloadedPageCountFromXml > 0) {
        downloadedPageCount = downloadedPageCountFromXml;
      } else if (totalPageCount > 0 && failedPageIndexes.length > 0) {
        downloadedPageCount = totalPageCount - failedPageIndexes.length;
      } else {
        downloadedPageCount = imageEntryCount;
      }
    } else {
      downloadedPageCount = totalPageCount > 0 ? totalPageCount : imageEntryCount;
    }

    if (totalPageCount <= 0 && downloadedPageCount > 0) {
      totalPageCount = downloadedPageCount;
    }
    downloadedPageCount = this.clampPageCount(downloadedPageCount, totalPageCount);
    const cacheStatus = this.resolveArchiveCacheStatus(isPartialArchive, downloadedPageCount, totalPageCount);

    const state: OnlineArchiveCacheState = {
      archivePath: archivePath,
      archiveSize: this.getFileSize(archivePath),
      totalPageCount: totalPageCount,
      downloadedPageCount: downloadedPageCount,
      failedPageIndexes: failedPageIndexes,
      isPartialArchive: isPartialArchive,
      hasComicInfo: hasComicInfo,
      imageEntryCount: imageEntryCount,
      cacheStatus: cacheStatus,
      storageType: OnlineChapterArchiveStorageType.CBZ
    };
    return state;
  }

  private resolveArchiveCacheStatus(
    isPartialArchive: boolean,
    downloadedPageCount: number,
    totalPageCount: number
  ): OnlineChapterArchiveCacheStatus {
    if (downloadedPageCount <= 0) {
      return OnlineChapterArchiveCacheStatus.STALE;
    }
    if (totalPageCount > 0 && downloadedPageCount >= totalPageCount && !isPartialArchive) {
      return OnlineChapterArchiveCacheStatus.COMPLETE;
    }
    if (totalPageCount <= 0 && downloadedPageCount > 0 && !isPartialArchive) {
      return OnlineChapterArchiveCacheStatus.COMPLETE;
    }
    return OnlineChapterArchiveCacheStatus.PARTIAL;
  }

  private serializeFailedPageIndexes(indexes: number[]): string {
    if (indexes.length <= 0) {
      return '';
    }
    const normalized: number[] = [];
    for (let i = 0; i < indexes.length; i++) {
      const index = indexes[i];
      if (!this.isUsableNumber(index) || index < 0) {
        continue;
      }
      const safeIndex = Math.floor(index);
      if (!normalized.includes(safeIndex)) {
        normalized.push(safeIndex);
      }
    }
    normalized.sort((left: number, right: number) => left - right);
    const parts: string[] = [];
    for (let i = 0; i < normalized.length; i++) {
      parts.push(String(normalized[i]));
    }
    return parts.join(',');
  }

  private normalizeFailedPageIndexesForTotal(indexes: number[], totalPageCount: number): number[] {
    const normalized: number[] = [];
    if (indexes.length <= 0) {
      return normalized;
    }
    const shouldConvertOneBased = totalPageCount > 0 && indexes.includes(totalPageCount);
    for (let i = 0; i < indexes.length; i++) {
      const rawIndex = indexes[i];
      if (!this.isUsableNumber(rawIndex)) {
        continue;
      }
      const convertedIndex = shouldConvertOneBased && rawIndex > 0
        ? Math.floor(rawIndex) - 1
        : Math.floor(rawIndex);
      if (convertedIndex < 0) {
        continue;
      }
      if (totalPageCount > 0 && convertedIndex >= totalPageCount) {
        continue;
      }
      if (!normalized.includes(convertedIndex)) {
        normalized.push(convertedIndex);
      }
    }
    normalized.sort((left: number, right: number) => left - right);
    return normalized;
  }

  private async persistOnlineArchiveCacheState(
    comic: OnlineComicInfo,
    chapter: OnlineChapterInfo,
    archiveState: OnlineArchiveCacheState
  ): Promise<void> {
    const pageCount = archiveState.totalPageCount > 0
      ? archiveState.totalPageCount
      : (chapter.pageCount || archiveState.downloadedPageCount);
    const isChapterFullyDownloaded = archiveState.cacheStatus === OnlineChapterArchiveCacheStatus.COMPLETE;
    const downloadedPageIds = archiveState.isPartialArchive
      ? await this.resolveDownloadedPageIdsForArchiveState(chapter.id, archiveState)
      : [];
    const now = Date.now();
    const existingRecord = await this.getOnlineChapterArchiveCacheState(chapter.id);
    const createTime = existingRecord !== null && existingRecord.createTime > 0 ? existingRecord.createTime : now;
    const failedPageIndexesText = this.serializeFailedPageIndexes(archiveState.failedPageIndexes);

    await this.databaseManager.beginTransaction();
    try {
      await this.databaseManager.executeSql(
        `INSERT OR REPLACE INTO online_chapter_cache_state
         (chapterId, comicId, sourceId, sourceName, sourcePkg, archivePath, cacheStatus, storageType, cachedPageCount, totalPageCount, archiveSize, imageEntryCount, hasComicInfo, failedPageIndexes, lastScanTime, createTime, updateTime)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          chapter.id,
          chapter.comicId,
          comic.sourceId,
          comic.sourceName,
          comic.sourcePkg,
          archiveState.archivePath,
          archiveState.cacheStatus,
          archiveState.storageType,
          archiveState.downloadedPageCount,
          pageCount,
          archiveState.archiveSize,
          archiveState.imageEntryCount,
          archiveState.hasComicInfo ? 1 : 0,
          failedPageIndexesText,
          now,
          createTime,
          now
        ]
      );
      await this.databaseManager.executeSql(
        'UPDATE online_chapter SET isDownloaded = ?, downloadPath = ?, pageCount = ?, updateTime = ? WHERE id = ?',
        [
          isChapterFullyDownloaded ? 1 : 0,
          archiveState.archivePath,
          pageCount,
          now,
          chapter.id
        ]
      );

      if (isChapterFullyDownloaded) {
        await this.databaseManager.executeSql(
          'UPDATE online_page SET isDownloaded = 1 WHERE chapterId = ?',
          [chapter.id]
        );
      } else {
        await this.databaseManager.executeSql(
          'UPDATE online_page SET isDownloaded = 0 WHERE chapterId = ?',
          [chapter.id]
        );
        for (let i = 0; i < downloadedPageIds.length; i++) {
          await this.databaseManager.executeSql(
            'UPDATE online_page SET isDownloaded = 1 WHERE id = ?',
            [downloadedPageIds[i]]
          );
        }
      }

      await this.databaseManager.commit();
    } catch (error) {
      await this.databaseManager.rollBack();
      throw error as Error;
    }
  }

  private async persistOnlineArchiveLookupMiss(
    comic: OnlineComicInfo,
    chapter: OnlineChapterInfo,
    reason: string
  ): Promise<void> {
    const rawDownloadPath = this.normalizeFileSystemPath(chapter.downloadPath || '');
    const stale = rawDownloadPath.length > 0 && this.isCbzPath(rawDownloadPath);
    const cacheStatus = stale ? OnlineChapterArchiveCacheStatus.STALE : OnlineChapterArchiveCacheStatus.NONE;
    const storageType = OnlineChapterArchiveStorageType.NONE;
    const knownPageCount = Math.max(chapter.pageCount || 0, await this.resolveKnownOnlineChapterPageCount(chapter.id));
    const now = Date.now();
    const existingRecord = await this.getOnlineChapterArchiveCacheState(chapter.id);
    const createTime = existingRecord !== null && existingRecord.createTime > 0 ? existingRecord.createTime : now;
    await this.databaseManager.beginTransaction();
    try {
      await this.databaseManager.executeSql(
        `INSERT OR REPLACE INTO online_chapter_cache_state
         (chapterId, comicId, sourceId, sourceName, sourcePkg, archivePath, cacheStatus, storageType, cachedPageCount, totalPageCount, archiveSize, imageEntryCount, hasComicInfo, failedPageIndexes, lastScanTime, createTime, updateTime)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          chapter.id,
          chapter.comicId,
          comic.sourceId,
          comic.sourceName,
          comic.sourcePkg,
          stale ? rawDownloadPath : '',
          cacheStatus,
          storageType,
          0,
          knownPageCount,
          0,
          0,
          0,
          '',
          now,
          createTime,
          now
        ]
      );
      await this.databaseManager.executeSql(
        'UPDATE online_chapter SET isDownloaded = 0, downloadPath = ?, pageCount = ?, updateTime = ? WHERE id = ?',
        [
          stale ? rawDownloadPath : null,
          knownPageCount,
          now,
          chapter.id
        ]
      );
      await this.databaseManager.executeSql(
        'UPDATE online_page SET isDownloaded = 0 WHERE chapterId = ?',
        [chapter.id]
      );
      await this.databaseManager.commit();
      logger.info(TAG, `在线章节归档缺失状态已记录: chapter=${chapter.title}, status=${cacheStatus}, reason=${reason}`);
    } catch (error) {
      await this.databaseManager.rollBack();
      throw error as Error;
    }
  }

  private async resolveDownloadedPageIdsForArchiveState(
    chapterId: string,
    archiveState: OnlineArchiveCacheState
  ): Promise<string[]> {
    const pages = await this.dataManager.getOnlineChapterPages(chapterId);
    const downloadedPageIds: string[] = [];
    if (pages.length <= 0 || archiveState.downloadedPageCount <= 0) {
      return downloadedPageIds;
    }

    const failedPageIndexes = new Set<number>();
    for (let i = 0; i < archiveState.failedPageIndexes.length; i++) {
      failedPageIndexes.add(archiveState.failedPageIndexes[i]);
    }
    const hasFailedPageList = failedPageIndexes.size > 0;
    const effectiveTotalPageCount = archiveState.totalPageCount > 0
      ? archiveState.totalPageCount
      : pages.length;

    for (let i = 0; i < pages.length; i++) {
      if (i >= effectiveTotalPageCount) {
        break;
      }
      let isDownloaded = false;
      if (hasFailedPageList) {
        isDownloaded = !failedPageIndexes.has(i);
      } else {
        isDownloaded = i < archiveState.downloadedPageCount;
      }
      if (isDownloaded) {
        downloadedPageIds.push(pages[i].id);
      }
    }
    return downloadedPageIds;
  }

  private readArchiveEntryInfo(archivePath: string): ArchiveEntryReadInfo {
    const emptyInfo: ArchiveEntryReadInfo = {
      entryNames: [],
      comicInfoXml: ''
    };
    try {
      const minizip = new MinizipNative(archivePath);
      const openCode = minizip.Open();
      if (openCode !== 0) {
        logger.warn(TAG, `读取CBZ条目失败: openCode=${openCode}, path=${archivePath}`);
        return emptyInfo;
      }

      const entryNames = minizip.GetEntryNames();
      let comicInfoXml = '';
      for (let i = 0; i < entryNames.length; i++) {
        const normalizedEntryName = this.normalizeArchiveEntryName(entryNames[i]);
        if (normalizedEntryName === 'comicinfo.xml' || normalizedEntryName.endsWith('/comicinfo.xml')) {
          const content = minizip.ExtractFileToJS(entryNames[i], '');
          if (content !== undefined) {
            comicInfoXml = this.decodeUtf8Text(content);
          }
          break;
        }
      }

      const info: ArchiveEntryReadInfo = {
        entryNames: entryNames,
        comicInfoXml: comicInfoXml
      };
      return info;
    } catch (error) {
      logger.warn(TAG, `读取CBZ元数据失败: ${archivePath}, ${String(error)}`);
      return emptyInfo;
    }
  }

  private countArchiveImageEntries(entryNames: string[]): number {
    let count = 0;
    for (let i = 0; i < entryNames.length; i++) {
      const normalizedEntryName = this.normalizeArchiveEntryName(entryNames[i]);
      if (normalizedEntryName.length <= 0 || normalizedEntryName.endsWith('/')) {
        continue;
      }
      if (this.isImagePath(normalizedEntryName)) {
        count++;
      }
    }
    return count;
  }

  private normalizeArchiveEntryName(entryName: string): string {
    return entryName.replace(/\\/g, '/').replace(/^\/+/, '').trim().toLowerCase();
  }

  private decodeUtf8Text(content: ArrayBuffer): string {
    const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    return decoder.decodeToString(new Uint8Array(content));
  }

  private parsePositiveIntegerXmlField(xmlContent: string, fieldName: string): number {
    const value = this.extractXmlFieldText(xmlContent, fieldName);
    if (value.length <= 0) {
      return 0;
    }
    const parsed = Number(value);
    if (!this.isUsableNumber(parsed) || parsed <= 0) {
      return 0;
    }
    return Math.floor(parsed);
  }

  private parseBooleanXmlField(xmlContent: string, fieldName: string): boolean {
    const value = this.extractXmlFieldText(xmlContent, fieldName).toLowerCase();
    return value === 'true' || value === '1' || value === 'yes';
  }

  private parseFailedPageIndexes(xmlContent: string): number[] {
    const value = this.extractXmlFieldText(xmlContent, 'FailedPages');
    const indexes: number[] = [];
    if (value.length <= 0) {
      return indexes;
    }
    const parts = value.split(',');
    for (let i = 0; i < parts.length; i++) {
      const parsed = Number(parts[i].trim());
      if (this.isUsableNumber(parsed) && parsed >= 0) {
        indexes.push(Math.floor(parsed));
      }
    }
    return indexes;
  }

  private extractXmlFieldText(xmlContent: string, fieldName: string): string {
    const pattern = new RegExp(`<${fieldName}[^>]*>([\\s\\S]*?)<\\/${fieldName}>`, 'i');
    const match = pattern.exec(xmlContent);
    if (!match || match.length < 2) {
      return '';
    }
    return match[1].trim();
  }

  private clampPageCount(pageCount: number, totalPageCount: number): number {
    if (pageCount <= 0) {
      return 0;
    }
    if (totalPageCount > 0 && pageCount > totalPageCount) {
      return totalPageCount;
    }
    return pageCount;
  }

  private recoverArchiveTempFile(archivePath: string): string {
    const tempPaths = this.buildArchiveTempPathCandidates(archivePath);
    for (let i = 0; i < tempPaths.length; i++) {
      const tempPath = tempPaths[i];
      if (!this.pathExists(tempPath)) {
        continue;
      }

      try {
        this.deleteFileIfExists(archivePath);
        SafeFileUtils.renameSync(tempPath, archivePath);
        this.deleteArchiveTempFiles(archivePath);
        logger.info(TAG, `已恢复未完成CBZ归档: ${tempPath} -> ${archivePath}`);
        return archivePath;
      } catch (error) {
        logger.warn(TAG, `恢复未完成CBZ归档失败: ${tempPath}, ${String(error)}`);
      }
    }
    return '';
  }

  private getPrivateArchiveDirectory(sourceName: string, mangaTitle: string, chapterTitle: string): string {
    const context = this.requireContext();
    const sourceSegment = this.sanitizePathSegment(sourceName.length > 0 ? sourceName : 'unknown_source');
    const mangaSegment = this.sanitizePathSegment(mangaTitle.length > 0 ? mangaTitle : 'unknown_manga');
    const chapterSegment = this.sanitizePathSegment(chapterTitle.length > 0 ? chapterTitle : 'unknown_chapter');
    const dir = `${context.filesDir}/downloads/online_archive/${sourceSegment}/${mangaSegment}/${chapterSegment}`;
    this.ensureDirectory(dir);
    return dir;
  }

  private createWorkDir(chapterId: string): string {
    const context = this.requireContext();
    const dir = `${context.cacheDir}/online_archive_work/${this.sanitizePathSegment(chapterId)}_${Date.now()}`;
    this.ensureDirectory(dir);
    return dir;
  }

  private resolveReaderExtractDir(chapterId: string, archivePath: string): string {
    const context = this.requireContext();
    const stat = SafeFileUtils.statSync(archivePath);
    const stamp = `${stat.size}_${stat.mtime}`;
    const dir = `${context.cacheDir}/online_cbz_reader/${this.sanitizePathSegment(chapterId)}_${this.sanitizePathSegment(stamp)}`;
    return dir;
  }

  private requireContext(): common.UIAbilityContext {
    if (!this.context) {
      throw new Error('在线漫画归档服务未设置应用上下文');
    }
    return this.context;
  }

  private buildArchiveLockKey(chapterId: string, archivePath: string): string {
    return `${chapterId}::${archivePath}`;
  }

  private async acquireArchiveLock(lockKey: string): Promise<void> {
    let waitCount = 0;
    while (this.activeArchiveLocks.has(lockKey)) {
      if (waitCount === 0) {
        logger.info(TAG, `归档锁等待: ${lockKey}`);
      }
      waitCount++;
      if (waitCount > 1200) {
        throw new Error(`等待归档锁超时: ${lockKey}`);
      }
      await this.sleep(100);
    }
    this.activeArchiveLocks.add(lockKey);
    if (waitCount > 0) {
      logger.info(TAG, `归档锁等待结束: ${lockKey}, waitMs=${waitCount * 100}`);
    } else {
      logger.debug(TAG, `归档锁已获取: ${lockKey}`);
    }
  }

  private releaseArchiveLock(lockKey: string): void {
    if (this.activeArchiveLocks.delete(lockKey)) {
      logger.debug(TAG, `归档锁已释放: ${lockKey}`);
    }
  }

  private buildUniqueTempArchivePath(archivePath: string): string {
    this.archiveTempSequence++;
    if (this.archiveTempSequence > 999999) {
      this.archiveTempSequence = 1;
    }
    return `${archivePath}.${Date.now()}_${this.archiveTempSequence}.tmp.zip`;
  }

  private async yieldArchiveBatch(index: number): Promise<void> {
    if (index > 0 && index % 8 === 0) {
      await this.yieldToEventLoop();
    }
  }

  private async yieldToEventLoop(): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout(resolve, 0);
    });
  }

  private async sleep(ms: number): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout(resolve, ms);
    });
  }

  private ensureDirectory(dirPath: string): void {
    try {
      const stat = SafeFileUtils.statSync(dirPath);
      if (!stat.isDirectory()) {
        throw new Error('路径不是目录');
      }
    } catch (_error) {
      SafeFileUtils.mkdirSync(dirPath, true);
    }
  }

  private pathExists(path: string): boolean {
    try {
      return SafeFileUtils.accessSync(path);
    } catch (_error) {
      return false;
    }
  }

  private deleteFileIfExists(path: string): void {
    try {
      if (this.pathExists(path)) {
        SafeFileUtils.unlinkSync(path);
      }
    } catch (error) {
      logger.warn(TAG, `删除文件失败: ${path}, ${String(error)}`);
    }
  }

  private deleteArchiveTempFiles(archivePath: string): void {
    const tempPaths = this.buildArchiveTempPathCandidates(archivePath);
    for (let i = 0; i < tempPaths.length; i++) {
      this.deleteFileIfExists(tempPaths[i]);
    }
  }

  private deleteUniqueArchiveTempFiles(tempArchivePath: string): void {
    this.deleteFileIfExists(tempArchivePath);
    this.deleteFileIfExists(`${tempArchivePath}.zip`);
  }

  private buildArchiveTempPathCandidates(archivePath: string): string[] {
    const legacyTempArchivePath = `${archivePath}.tmp`;
    const zipTempArchivePath = `${archivePath}.tmp.zip`;
    const paths: string[] = [];
    paths.push(zipTempArchivePath);
    paths.push(`${zipTempArchivePath}.zip`);
    paths.push(legacyTempArchivePath);
    paths.push(`${legacyTempArchivePath}.zip`);
    return this.deduplicatePaths(paths);
  }

  private resolveCompressedOutputPath(tempArchivePath: string, legacyTempArchivePath: string): string {
    const candidates: string[] = [];
    candidates.push(tempArchivePath);
    candidates.push(`${tempArchivePath}.zip`);
    candidates.push(legacyTempArchivePath);
    candidates.push(`${legacyTempArchivePath}.zip`);

    for (let i = 0; i < candidates.length; i++) {
      if (this.pathExists(candidates[i])) {
        return candidates[i];
      }
    }
    throw new Error(`压缩输出文件不存在: ${candidates.join(', ')}`);
  }

  private async deleteDirectoryRecursiveAsync(dirPath: string): Promise<void> {
    try {
      if (!this.pathExists(dirPath)) {
        return;
      }
      const entries = SafeFileUtils.listFileSync(dirPath);
      for (let i = 0; i < entries.length; i++) {
        const fullPath = `${dirPath}/${entries[i]}`;
        const stat = SafeFileUtils.statSync(fullPath);
        if (stat.isDirectory()) {
          await this.deleteDirectoryRecursiveAsync(fullPath);
        } else {
          SafeFileUtils.unlinkSync(fullPath);
        }
        await this.yieldArchiveBatch(i);
      }
      SafeFileUtils.rmdirSync(dirPath);
    } catch (error) {
      logger.warn(TAG, `异步分批删除目录失败: ${dirPath}, ${String(error)}`);
    }
  }

  private async writeTextFile(path: string, content: string): Promise<void> {
    const encoder = new util.TextEncoder();
    const buffer = encoder.encodeInto(content);
    await this.writeArrayBufferToFile(path, buffer.buffer as ArrayBuffer);
  }

  private async writeArrayBufferToFile(path: string, content: ArrayBuffer): Promise<void> {
    let file: fs.File | null = null;
    let operationError: Error | null = null;
    try {
      file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      await fs.write(file.fd, content);
    } catch (error) {
      operationError = error as Error;
      throw operationError;
    } finally {
      if (file !== null) {
        try {
          await fs.close(file);
        } catch (closeError) {
          logger.warn(TAG, `关闭归档写入文件句柄失败: ${path}, ${String(closeError)}`);
          if (operationError === null) {
            throw closeError as Error;
          }
        }
      }
    }
  }

  private getFileSize(path: string): number {
    try {
      const stat = SafeFileUtils.statSync(path);
      return stat.size;
    } catch (_error) {
      return 0;
    }
  }

  private hasReadableExtractedImages(dirPath: string): boolean {
    if (!this.pathExists(dirPath)) {
      return false;
    }
    const imageFiles = this.scanImageFilesRecursive(dirPath);
    return imageFiles.length > 0;
  }

  private scanImageFilesRecursive(dirPath: string): string[] {
    const files: string[] = [];
    if (!this.pathExists(dirPath)) {
      return files;
    }

    const entries = SafeFileUtils.listFileSync(dirPath);
    for (let i = 0; i < entries.length; i++) {
      const fullPath = `${dirPath}/${entries[i]}`;
      const stat = SafeFileUtils.statSync(fullPath);
      if (stat.isDirectory()) {
        const childFiles = this.scanImageFilesRecursive(fullPath);
        for (let j = 0; j < childFiles.length; j++) {
          files.push(childFiles[j]);
        }
      } else if (this.isImagePath(fullPath)) {
        files.push(fullPath);
      }
    }

    files.sort((left: string, right: string) => {
      return this.extractSortNumber(left) - this.extractSortNumber(right);
    });
    return files;
  }

  private isImagePath(path: string): boolean {
    const extension = this.getPathExtension(path);
    return this.supportedImageExtensions.includes(extension);
  }

  private isCbzPath(path: string): boolean {
    return path.toLowerCase().endsWith('.cbz');
  }

  private resolveImageExtension(path: string, imageUrl: string): string {
    const pathExtension = this.getPathExtension(path);
    if (this.supportedImageExtensions.includes(pathExtension)) {
      return pathExtension;
    }
    const urlExtension = this.getPathExtension(imageUrl.split('?')[0]);
    if (this.supportedImageExtensions.includes(urlExtension)) {
      return urlExtension;
    }
    return 'jpg';
  }

  private getPathExtension(path: string): string {
    const normalizedPath = path.split('?')[0];
    const slashIndex = Math.max(normalizedPath.lastIndexOf('/'), normalizedPath.lastIndexOf('\\'));
    const fileName = slashIndex >= 0 ? normalizedPath.substring(slashIndex + 1) : normalizedPath;
    const dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex === fileName.length - 1) {
      return '';
    }
    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  private extractSortNumber(path: string): number {
    const slashIndex = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
    const fileName = slashIndex >= 0 ? path.substring(slashIndex + 1) : path;
    const digits = fileName.replace(/[^0-9]/g, '');
    if (digits.length === 0) {
      return Number.MAX_SAFE_INTEGER;
    }
    return Number(digits);
  }

  private sanitizePathSegment(name: string): string {
    const trimmed = name.trim();
    const safeName = trimmed.length > 0 ? trimmed : 'unnamed';
    return safeName
      .replace(/[\\/:*?"<>|]/g, '_')
      .replace(/\s+/g, ' ')
      .trim()
      .substring(0, 100);
  }

  private escapeXml(text: string): string {
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }
}

export function getOnlineMangaArchiveService(): OnlineMangaArchiveService {
  return OnlineMangaArchiveService.getInstance();
}
