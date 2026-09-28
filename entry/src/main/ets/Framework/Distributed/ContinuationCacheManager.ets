import fileIo from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import {
  EBook,
  EBookFormat,
  EBookReadingProgress,
  EBookReadingSettings,
  EBookStatus
} from 'manxia_core/src/main/ets/Models/EBookModels';
import { NovelBook, NovelChapter } from 'manxia_core/src/main/ets/Models/NovelModels';
import {
  DEFAULT_READING_SETTINGS,
  ImageSourceType,
  Manga,
  MangaChapter,
  MangaMetadata,
  MangaPage,
  ReadingSettings
} from 'manxia_core/src/main/ets/Models/MangaModels';
import { DownloadStatus, MangaStatus, ReadingStatus } from 'manxia_core/src/main/ets/Framework/Types/StatusEnums';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import {
  ContinuationCacheProgress,
  ContinuationCacheRecord,
  ContinuationContentType,
  ContinuationTransferFile,
  ContinuationTransferManifest,
  ContinuationTransferMode
} from './ContinuationReadingTypes';
import { MangaTransferBundle } from './MangaTransferTypes';
import { normalizeContinuationPackagePath } from './ContinuationTransferManifestValidator';

const TAG = 'ContinuationCacheManager';
const CACHE_DIRECTORY_NAME = 'continuation_read';
const RECORD_FILE_NAME = 'record.json';
const MANIFEST_FILE_NAME = 'manifest.json';

export class ContinuationCacheManager {
  private static instance: ContinuationCacheManager | null = null;
  private rootDirectory: string = '';
  private initialized: boolean = false;

  private constructor() {}

  public static getInstance(): ContinuationCacheManager {
    if (!ContinuationCacheManager.instance) {
      ContinuationCacheManager.instance = new ContinuationCacheManager();
    }
    return ContinuationCacheManager.instance;
  }

  public async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized && this.rootDirectory.length > 0) {
      return;
    }
    const cacheRoot = `${context.cacheDir}/${CACHE_DIRECTORY_NAME}`;
    if (SafeFileUtils.accessSync(cacheRoot)) {
      if (!SafeFileUtils.statSyncStrict(cacheRoot).isDirectory()) {
        throw new Error(`接续阅读缓存路径不是目录: ${cacheRoot}`);
      }
    } else {
      SafeFileUtils.mkdirSyncStrict(cacheRoot, true);
    }
    this.rootDirectory = cacheRoot;
    this.initialized = true;
    logger.info(TAG, `接续阅读缓存目录就绪: ${this.rootDirectory}`);
  }

  public createCacheId(): string {
    return `continuation_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
  }

  public async commitReadOnlyPackage(
    cacheId: string,
    manifest: ContinuationTransferManifest,
    stagingDirectory: string
  ): Promise<ContinuationCacheRecord> {
    this.ensureInitialized();
    if (manifest.mode !== ContinuationTransferMode.READ_ONLY || manifest.schemaVersion !== 1) {
      throw new Error('接续缓存仅允许提交有效的只读数据包');
    }
    const safeCacheId = this.normalizeCacheId(cacheId);
    const targetDirectory = `${this.rootDirectory}/${safeCacheId}`;
    const pendingDirectory = `${this.rootDirectory}/.pending_${safeCacheId}`;
    let movedToTargetDirectory = false;
    this.deleteDirectoryIfPresent(pendingDirectory);
    SafeFileUtils.mkdirSyncStrict(pendingDirectory, true);
    try {
      this.copyDirectory(stagingDirectory, pendingDirectory);
      const normalizedManifest = this.normalizeManifestForCache(manifest);
      this.writeJson(`${pendingDirectory}/${MANIFEST_FILE_NAME}`, normalizedManifest);
      const record = this.createRecord(safeCacheId, normalizedManifest, pendingDirectory);
      this.writeJson(`${pendingDirectory}/${RECORD_FILE_NAME}`, record);
      this.deleteDirectoryIfPresent(targetDirectory);
      SafeFileUtils.renameSyncStrict(pendingDirectory, targetDirectory);
      movedToTargetDirectory = true;
      record.dataDirectory = targetDirectory;
      this.writeJson(`${targetDirectory}/${RECORD_FILE_NAME}`, record);
      logger.info(
        TAG,
        `只读接续包已提交缓存: cacheId=${safeCacheId}, sourceBookId=${record.sourceBookId}, type=${record.contentType}, bytes=${record.byteSize}`
      );
      return record;
    } catch (error) {
      this.deleteDirectoryIfPresent(pendingDirectory);
      if (movedToTargetDirectory) {
        this.deleteDirectoryIfPresent(targetDirectory);
      }
      throw error as Error;
    }
  }

  public async listRecords(): Promise<ContinuationCacheRecord[]> {
    this.ensureInitialized();
    const entries = SafeFileUtils.listFileSync(this.rootDirectory);
    const records: ContinuationCacheRecord[] = [];
    for (const entry of entries) {
      if (entry.startsWith('.pending_')) {
        continue;
      }
      const directory = `${this.rootDirectory}/${entry}`;
      const recordPath = `${directory}/${RECORD_FILE_NAME}`;
      if (!SafeFileUtils.accessSync(recordPath)) {
        continue;
      }
      try {
        const parsed = JSON.parse(SafeFileUtils.readTextSync(recordPath)) as ContinuationCacheRecord;
        if (parsed.cacheId.length <= 0 || parsed.sourceBookId.length <= 0 || !this.isDirectory(directory)) {
          continue;
        }
        parsed.dataDirectory = directory;
        records.push(parsed);
      } catch (error) {
        logger.warn(TAG, `忽略损坏的接续缓存记录: ${recordPath}, ${String(error)}`);
      }
    }
    records.sort((first: ContinuationCacheRecord, second: ContinuationCacheRecord): number =>
      second.lastReadTime - first.lastReadTime
    );
    return records;
  }

  public async getRecord(cacheId: string): Promise<ContinuationCacheRecord | null> {
    const safeCacheId = this.normalizeCacheId(cacheId);
    const records = await this.listRecords();
    for (const record of records) {
      if (record.cacheId === safeCacheId) {
        return record;
      }
    }
    return null;
  }

  public async getManifest(cacheId: string): Promise<ContinuationTransferManifest | null> {
    const record = await this.getRecord(cacheId);
    if (!record) {
      return null;
    }
    const manifestPath = `${record.dataDirectory}/${MANIFEST_FILE_NAME}`;
    try {
      return JSON.parse(SafeFileUtils.readTextSync(manifestPath)) as ContinuationTransferManifest;
    } catch (error) {
      logger.warn(TAG, `读取接续缓存清单失败: cacheId=${cacheId}, ${String(error)}`);
      return null;
    }
  }

  public async getEBook(cacheId: string): Promise<EBook | null> {
    const manifest = await this.getManifest(cacheId);
    const record = await this.getRecord(cacheId);
    if (!manifest || !manifest.ebook || !record) {
      return null;
    }
    const localTextEBookId = manifest.contentType === 'novel' && manifest.isLocal
      ? manifest.ebook.id
      : manifest.sourceBookId;
    const ebook = this.materializeEBook(manifest, record.dataDirectory, localTextEBookId);
    if (!ebook) {
      return null;
    }
    ebook.readingProgress.currentChapterIndex = record.chapterIndex;
    ebook.readingProgress.currentPosition = record.offset > 0 ? record.offset : record.pageIndex;
    ebook.readingProgress.lastReadTime = record.lastReadTime;
    return ebook;
  }

  public materializeEBook(
    manifest: ContinuationTransferManifest,
    dataDirectory: string,
    targetBookId: string
  ): EBook | null {
    if (!manifest.ebook) {
      return null;
    }
    const snapshot = manifest.ebook;
    const ebook = new EBook(
      targetBookId,
      snapshot.format as EBookFormat,
      this.resolvePath(dataDirectory, snapshot.filePath),
      snapshot.fileSize,
      snapshot.metadata,
      snapshot.chapters,
      snapshot.status as EBookStatus,
      snapshot.readingProgress,
      snapshot.readingSettings,
      snapshot.addTime,
      snapshot.lastUpdateTime,
      snapshot.isFavorite,
      snapshot.totalWordCount,
      snapshot.isPrivate,
      snapshot.isNSFW
    );
    ebook.contentMode = snapshot.contentMode;
    ebook.preferredReaderEngine = snapshot.preferredReaderEngine;
    ebook.extractedRootPath = this.resolvePath(dataDirectory, snapshot.extractedRootPath);
    ebook.metadata.coverImagePath = this.resolvePath(dataDirectory, snapshot.metadata.coverImagePath);
    ebook.chapters = snapshot.chapters;
    for (const chapter of ebook.chapters) {
      chapter.bookId = targetBookId;
      chapter.resourceImagePath = this.resolvePath(dataDirectory, chapter.resourceImagePath ?? '');
    }
    for (const content of manifest.chapterContents) {
      if (content.chapterIndex >= 0 && content.chapterIndex < ebook.chapters.length) {
        const contentPath = this.resolvePath(dataDirectory, content.relativePath);
        if (contentPath.length > 0 && SafeFileUtils.accessSync(contentPath)) {
          ebook.chapters[content.chapterIndex].content = SafeFileUtils.readTextSync(contentPath);
        }
      }
    }
    ebook.id = targetBookId;
    ebook.readingProgress.bookId = targetBookId;
    return ebook;
  }

  public async getMangaBundle(cacheId: string): Promise<MangaTransferBundle | null> {
    const manifest = await this.getManifest(cacheId);
    const record = await this.getRecord(cacheId);
    if (!manifest || !manifest.manga || !record) {
      return null;
    }
    return this.materializeMangaBundle(manifest, record.dataDirectory);
  }

  public materializeMangaBundle(
    manifest: ContinuationTransferManifest,
    dataDirectory: string
  ): MangaTransferBundle | null {
    if (!manifest.manga) {
      return null;
    }
    const bundle = manifest.manga;
    bundle.comic.coverLocalPath = this.resolvePath(dataDirectory, bundle.comic.coverLocalPath);
    for (const chapter of bundle.chapters) {
      chapter.downloadPath = this.resolvePath(dataDirectory, chapter.downloadPath);
    }
    for (const group of bundle.chapterPages) {
      for (const page of group.pages) {
        page.localPath = this.resolvePath(dataDirectory, page.localPath);
      }
    }
    for (const file of bundle.files) {
      file.originalPath = this.resolvePath(dataDirectory, file.relPath);
    }
    return bundle;
  }

  public copyPackageDirectory(sourceDirectory: string, targetDirectory: string): void {
    this.ensureInitialized();
    this.deleteDirectoryIfPresent(targetDirectory);
    SafeFileUtils.mkdirSyncStrict(targetDirectory, true);
    this.copyDirectory(sourceDirectory, targetDirectory);
  }

  public deletePackageDirectory(path: string): void {
    this.deleteDirectoryIfPresent(path);
  }

  public async getManga(cacheId: string): Promise<Manga | null> {
    const record = await this.getRecord(cacheId);
    const bundle = await this.getMangaBundle(cacheId);
    if (!record || !bundle) {
      return null;
    }
    const metadata: MangaMetadata = {
      authors: bundle.comic.author.length > 0 ? [bundle.comic.author] : [],
      artists: [],
      genres: bundle.comic.tags,
      themes: [],
      demographics: [],
      publicationYear: undefined,
      publisher: ''
    };
    const readingSettings = JSON.parse(JSON.stringify(DEFAULT_READING_SETTINGS)) as ReadingSettings;
    const manga: Manga = {
      id: record.sourceBookId,
      title: bundle.comic.title,
      alternativeTitles: [],
      description: bundle.comic.description,
      coverImagePath: bundle.comic.coverLocalPath || bundle.comic.coverUrl,
      coverSourceType: bundle.comic.coverLocalPath.length > 0 ? ImageSourceType.LOCAL : ImageSourceType.NETWORK,
      status: bundle.comic.status as MangaStatus,
      metadata: metadata,
      chapters: [],
      readingProgress: {
        currentChapterId: '',
        currentPageIndex: record.pageIndex,
        readingStatus: ReadingStatus.READING,
        totalReadingTime: 0,
        lastReadAt: record.lastReadTime,
        readingPercentage: 0
      },
      bookmarks: [],
      readingSettings: readingSettings,
      isFavorite: false,
      lastUpdatedAt: bundle.comic.lastUpdateTime,
      sourceInfo: {
        sourceName: record.sourceId,
        sourceUrl: '',
        sourceId: record.sourceId,
        externalId: bundle.comic.externalId,
        sourceLanguage: '',
        requiresLogin: false
      },
      contentType: bundle.comic.contentType,
      isNSFW: bundle.comic.isNSFW === 1,
      isPrivate: bundle.comic.isPrivate === 1
    };
    for (const remoteChapter of bundle.chapters) {
      const pageGroup = bundle.chapterPages.find(
        (entry) => entry.chapterId === remoteChapter.id
      );
      const pages: MangaPage[] = [];
      if (pageGroup) {
        for (const remotePage of pageGroup.pages) {
          const localPath = remotePage.localPath || '';
          const page: MangaPage = {
            id: remotePage.id,
            index: remotePage.index,
            sourceType: localPath.length > 0 ? ImageSourceType.LOCAL : ImageSourceType.NETWORK,
            imagePath: localPath.length > 0 ? localPath : remotePage.imageUrl,
            imageUrl: remotePage.imageUrl,
            localPath: localPath,
            width: remotePage.width,
            height: remotePage.height,
            fileSize: remotePage.fileSize,
            isLoaded: false
          };
          pages.push(page);
        }
      }
      const chapter: MangaChapter = {
        id: remoteChapter.id,
        externalId: remoteChapter.externalId,
        title: remoteChapter.title,
        chapterNumber: remoteChapter.index + 1,
        pages: pages,
        totalPages: remoteChapter.pageCount,
        publishDate: remoteChapter.publishTime,
        language: '',
        scanlationGroup: '',
        isDownloaded: remoteChapter.isDownloaded,
        downloadStatus: remoteChapter.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
        downloadProgress: remoteChapter.isDownloaded ? 100 : 0,
        localPath: remoteChapter.downloadPath
      };
      manga.chapters.push(chapter);
      if (remoteChapter.index === record.chapterIndex) {
        manga.readingProgress.currentChapterId = remoteChapter.id;
      }
    }
    return manga;
  }

  public async getNovelBook(cacheId: string): Promise<NovelBook | null> {
    const manifest = await this.getManifest(cacheId);
    const record = await this.getRecord(cacheId);
    if (!manifest || !manifest.novelBook || !record) {
      return null;
    }
    const book = manifest.novelBook;
    book.id = record.cacheId;
    book.lastReadChapterIndex = record.chapterIndex;
    book.lastReadPosition = record.offset;
    book.lastReadTime = record.lastReadTime;
    return book;
  }

  public async getNovelChapters(cacheId: string): Promise<NovelChapter[]> {
    const manifest = await this.getManifest(cacheId);
    return manifest ? manifest.novelChapters : [];
  }

  public async getNovelChapterContent(cacheId: string, chapterIndex: number): Promise<string | null> {
    const manifest = await this.getManifest(cacheId);
    const record = await this.getRecord(cacheId);
    if (!manifest || !record) {
      return null;
    }
    for (const content of manifest.chapterContents) {
      if (content.chapterIndex === chapterIndex) {
        const path = this.resolveCachedPath(record, content.relativePath);
        if (path.length > 0 && SafeFileUtils.accessSync(path)) {
          return SafeFileUtils.readTextSync(path);
        }
      }
    }
    return null;
  }

  public isCacheId(value: string): boolean {
    return value.startsWith('continuation_');
  }

  public async resolveFile(cacheId: string, relativePath: string): Promise<string> {
    const record = await this.getRecord(cacheId);
    if (!record) {
      return '';
    }
    return this.resolveCachedPath(record, relativePath);
  }

  public async updateProgress(cacheId: string, progress: ContinuationCacheProgress): Promise<void> {
    const record = await this.getRecord(cacheId);
    if (!record) {
      return;
    }
    record.chapterIndex = Math.max(0, Math.floor(progress.chapterIndex));
    record.pageIndex = Math.max(0, Math.floor(progress.pageIndex));
    record.offset = Math.max(0, Math.floor(progress.offset));
    record.lastReadTime = Math.max(record.lastReadTime, progress.lastReadTime);
    this.writeJson(`${record.dataDirectory}/${RECORD_FILE_NAME}`, record);
    const manifest = await this.getManifest(cacheId);
    if (manifest?.ebook) {
      const ebookProgress: EBookReadingProgress = manifest.ebook.readingProgress;
      ebookProgress.currentChapterIndex = record.chapterIndex;
      ebookProgress.currentPosition = record.offset > 0 ? record.offset : record.pageIndex;
      ebookProgress.lastReadTime = record.lastReadTime;
      ebookProgress.bookId = manifest.contentType === 'novel' && manifest.isLocal && manifest.ebook
        ? manifest.ebook.id
        : record.sourceBookId;
      this.writeJson(`${record.dataDirectory}/${MANIFEST_FILE_NAME}`, manifest);
    }
    AppStorage.setOrCreate('continuationCacheRevision', Date.now());
  }

  public async updateEBookSettings(cacheId: string, settings: EBookReadingSettings): Promise<void> {
    const record = await this.getRecord(cacheId);
    const manifest = await this.getManifest(cacheId);
    if (!record || !manifest?.ebook) {
      return;
    }
    manifest.ebook.readingSettings = settings;
    this.writeJson(`${record.dataDirectory}/${MANIFEST_FILE_NAME}`, manifest);
  }

  public async getCacheSize(): Promise<number> {
    this.ensureInitialized();
    return this.measureDirectory(this.rootDirectory);
  }

  public async deleteCache(cacheId: string): Promise<boolean> {
    const safeCacheId = this.normalizeCacheId(cacheId);
    const directory = `${this.rootDirectory}/${safeCacheId}`;
    if (!this.isDirectory(directory)) {
      return false;
    }
    this.deleteDirectoryIfPresent(directory);
    logger.info(TAG, `已清理接续阅读缓存: cacheId=${safeCacheId}`);
    return true;
  }

  public async clearAll(): Promise<number> {
    this.ensureInitialized();
    const records = await this.listRecords();
    const entries = SafeFileUtils.listFileSync(this.rootDirectory);
    for (const entry of entries) {
      this.deleteDirectoryIfPresent(`${this.rootDirectory}/${entry}`);
    }
    SafeFileUtils.mkdirSyncStrict(this.rootDirectory, true);
    logger.info(TAG, `已清理全部接续阅读缓存: records=${records.length}`);
    return records.length;
  }

  private createRecord(
    cacheId: string,
    manifest: ContinuationTransferManifest,
    dataDirectory: string
  ): ContinuationCacheRecord {
    const record: ContinuationCacheRecord = {
      cacheId: cacheId,
      sourceBookId: manifest.sourceBookId,
      contentType: manifest.contentType,
      title: manifest.title,
      author: manifest.author,
      coverPath: manifest.coverPath,
      sourceId: manifest.sourceId,
      bookUrl: manifest.bookUrl,
      chapterIndex: manifest.chapterIndex,
      pageIndex: manifest.pageIndex,
      offset: manifest.offset,
      lastReadTime: Date.now(),
      byteSize: this.measureDirectory(dataDirectory),
      dataDirectory: dataDirectory
    };
    return record;
  }

  private normalizeManifestForCache(manifest: ContinuationTransferManifest): ContinuationTransferManifest {
    const normalized: ContinuationTransferManifest = {
      schemaVersion: manifest.schemaVersion,
      sessionId: manifest.sessionId,
      mode: manifest.mode,
      contentType: manifest.contentType,
      sourceBookId: manifest.sourceBookId,
      isLocal: manifest.isLocal,
      title: manifest.title,
      author: manifest.author,
      coverPath: manifest.coverPath,
      sourceId: manifest.sourceId,
      sourceName: manifest.sourceName,
      bookUrl: manifest.bookUrl,
      chapterIndex: manifest.chapterIndex,
      pageIndex: manifest.pageIndex,
      offset: manifest.offset,
      chapterTitle: manifest.chapterTitle,
      chapterCount: manifest.chapterCount,
      isCompleteBook: manifest.isCompleteBook,
      ebook: manifest.ebook,
      manga: manifest.manga,
      novelBook: manifest.novelBook,
      novelChapters: manifest.novelChapters,
      chapterContents: manifest.chapterContents,
      files: manifest.files.map((sourceFile): ContinuationTransferFile => ({
        name: sourceFile.name,
        relativePath: sourceFile.relativePath,
        sourcePath: '',
        size: sourceFile.size,
        sha256: sourceFile.sha256
      }))
    };
    return normalized;
  }

  private resolveCachedPath(record: ContinuationCacheRecord, relativePath: string): string {
    return this.resolvePath(record.dataDirectory, relativePath);
  }

  private resolvePath(dataDirectory: string, relativePath: string): string {
    const normalized = relativePath.replace(/\\/g, '/').trim();
    if (normalized.length <= 0) {
      return '';
    }
    let relative = normalized;
    if (normalized.startsWith(`${dataDirectory}/`)) {
      relative = normalized.substring(dataDirectory.length + 1);
    }
    return `${dataDirectory}/${normalizeContinuationPackagePath(relative)}`;
  }

  private normalizeCacheId(cacheId: string): string {
    const safeId = cacheId.replace(/[^A-Za-z0-9_-]/g, '_');
    if (safeId.length <= 0) {
      throw new Error('Invalid continuation cache ID');
    }
    return safeId;
  }

  private writeJson(path: string, value: Object): void {
    const file = SafeFileUtils.openSyncStrict(
      path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
    );
    try {
      SafeFileUtils.writeStringExactSync(file.fd, JSON.stringify(value));
    } finally {
      SafeFileUtils.closeSync(file);
    }
  }

  private copyDirectory(sourceDirectory: string, targetDirectory: string): void {
    if (!this.isDirectory(sourceDirectory)) {
      throw new Error(`Continuation package staging directory is missing: ${sourceDirectory}`);
    }
    const entries = SafeFileUtils.listFileSync(sourceDirectory);
    for (const entry of entries) {
      const sourcePath = `${sourceDirectory}/${entry}`;
      const targetPath = `${targetDirectory}/${entry}`;
      const stat = SafeFileUtils.lstatSyncStrict(sourcePath);
      if (stat.isDirectory()) {
        SafeFileUtils.mkdirSyncStrict(targetPath, true);
        this.copyDirectory(sourcePath, targetPath);
      } else {
        SafeFileUtils.copyFileSyncStrict(sourcePath, targetPath);
      }
    }
  }

  private measureDirectory(path: string): number {
    if (!this.isDirectory(path)) {
      return 0;
    }
    let size = 0;
    for (const entry of SafeFileUtils.listFileSync(path)) {
      const itemPath = `${path}/${entry}`;
      const stat = SafeFileUtils.lstatSyncStrict(itemPath);
      if (stat.isDirectory()) {
        size += this.measureDirectory(itemPath);
      } else {
        size += Math.max(0, stat.size);
      }
    }
    return size;
  }

  private deleteDirectoryIfPresent(path: string): void {
    if (!this.isDirectory(path)) {
      if (SafeFileUtils.accessSync(path)) {
        SafeFileUtils.unlinkSync(path);
      }
      return;
    }
    for (const entry of SafeFileUtils.listFileSync(path)) {
      this.deleteDirectoryIfPresent(`${path}/${entry}`);
    }
    SafeFileUtils.rmdirSync(path);
  }

  private isDirectory(path: string): boolean {
    try {
      return SafeFileUtils.lstatSyncStrict(path).isDirectory();
    } catch (_error) {
      return false;
    }
  }

  private ensureInitialized(): void {
    if (!this.initialized || this.rootDirectory.length <= 0) {
      throw new Error('Continuation cache manager is not initialized');
    }
  }
}

export const continuationCacheManager = ContinuationCacheManager.getInstance();
