import fileIo from '@ohos.file.fs';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { EBook, EBookChapter, EBookMetadata, DEFAULT_EBOOK_READING_SETTINGS } from 'manxia_core/src/main/ets/Models/EBookModels';
import { NovelBook, NovelChapter, NovelReadStatus } from 'manxia_core/src/main/ets/Models/NovelModels';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { getContext } from 'manxia_core/src/main/ets/GlobalContext';
import { getTarPackager } from 'manxia_core/src/main/ets/Framework/Utils/TarPackager';
import { EBookDataManager } from 'manxia_core/src/main/ets/Framework/Data/EBookDataManager';
import { getNovelDataManager } from '../Novel/NovelDataManager';
import { getNovelChapterCacheManager } from '../Novel/NovelChapterCacheManager';
import {
  UnifiedDownloadManager,
  MangaChapterDownloadParams,
  getUnifiedDownloadManager,
  UnifiedTaskStatus
} from '../Download/UnifiedDownloadManager';
import { LegadoChapter } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';
import { getLocalTextNovelEBookId, LOCAL_TXT_NOVEL_SOURCE_ID } from '../Adapters/LocalTextNovelAdapter';
import {
  ContinuationChapterContent,
  ContinuationTransferFile,
  ContinuationTransferManifest,
  ContinuationTransferMode,
  ContinuationTransferRequest
} from './ContinuationReadingTypes';
import {
  MangaChapterPagesEntry,
  MangaTransferBundle,
  MangaTransferFileEntry,
  RemoteChapterMetadata,
  RemoteComicMetadata,
  RemotePageMetadata
} from './MangaTransferTypes';

const TAG = 'ContinuationTransferPackageBuilder';
const FILE_HASH_CHUNK_SIZE = 1024 * 1024;

export interface ContinuationTransferArchive {
  archivePath: string;
  packageDirectory: string;
  fileName: string;
  totalBytes: number;
  sha256: string;
  manifest: ContinuationTransferManifest;
}

export type MangaBundleProvider = () => Promise<MangaTransferBundle | null>;

function bytesToHex(bytes: Uint8Array): string {
  let result = '';
  const digits = '0123456789abcdef';
  for (let index = 0; index < bytes.length; index++) {
    const byte = bytes[index];
    result += digits.charAt((byte >> 4) & 0x0f);
    result += digits.charAt(byte & 0x0f);
  }
  return result;
}

export class ContinuationTransferPackageBuilder {
  public async build(
    request: ContinuationTransferRequest,
    mangaBundleProvider: MangaBundleProvider
  ): Promise<ContinuationTransferArchive | null> {
    if (request.mode === ContinuationTransferMode.DISABLED) {
      return null;
    }
    const context = getContext();
    const safeSessionId = this.sanitizeSegment(request.sessionId);
    const safeBookId = this.sanitizeSegment(request.sourceBookId);
    const packageDirectory = `${context.cacheDir}/continuation_source/${safeSessionId}_${safeBookId}`;
    const archivePath = `${context.cacheDir}/continuation_source/${safeSessionId}_${safeBookId}.tar`;
    this.deleteDirectoryIfPresent(packageDirectory);
    if (SafeFileUtils.accessSync(archivePath)) {
      SafeFileUtils.unlinkSyncStrict(archivePath);
    }
    SafeFileUtils.mkdirSyncStrict(packageDirectory, true);
    const manifest = this.createEmptyManifest(request);
    try {
      if (request.contentType === 'ebook') {
        await this.buildEBookPackage(request, manifest, packageDirectory);
      } else if (request.contentType === 'manga') {
        const bundle = await mangaBundleProvider();
        if (!bundle) {
          throw new Error(`源设备未找到漫画内容: ${request.sourceBookId}`);
        }
        await this.buildMangaPackage(request, manifest, packageDirectory, bundle, mangaBundleProvider);
      } else {
        await this.buildNovelPackage(request, manifest, packageDirectory);
      }
      this.writeJson(`${packageDirectory}/manifest.json`, manifest);
      await getTarPackager().createTarArchive(packageDirectory, archivePath);
      const stat = SafeFileUtils.statSyncStrict(archivePath);
      const sha256 = await this.computeFileHash(archivePath);
      if (stat.size <= 0 || sha256.length <= 0) {
        throw new Error('接续数据包为空或无法校验');
      }
      logger.info(
        TAG,
        `接续数据包已准备: type=${request.contentType}, mode=${request.mode}, files=${manifest.files.length}, bytes=${stat.size}`
      );
      return {
        archivePath: archivePath,
        packageDirectory: packageDirectory,
        fileName: `continuation_${safeBookId}.tar`,
        totalBytes: stat.size,
        sha256: sha256,
        manifest: manifest
      };
    } catch (error) {
      this.deleteDirectoryIfPresent(packageDirectory);
      if (SafeFileUtils.accessSync(archivePath)) {
        SafeFileUtils.unlinkSync(archivePath);
      }
      logger.warn(TAG, `准备接续数据包失败: type=${request.contentType}, error=${String(error)}`);
      return null;
    }
  }

  public cleanup(archive: ContinuationTransferArchive): void {
    this.deleteDirectoryIfPresent(archive.packageDirectory);
    if (SafeFileUtils.accessSync(archive.archivePath)) {
      SafeFileUtils.unlinkSync(archive.archivePath);
    }
  }

  private createEmptyManifest(request: ContinuationTransferRequest): ContinuationTransferManifest {
    const manifest: ContinuationTransferManifest = {
      schemaVersion: request.schemaVersion,
      sessionId: request.sessionId,
      mode: request.mode,
      contentType: request.contentType,
      sourceBookId: request.sourceBookId,
      isLocal: request.isLocal,
      title: '',
      author: '',
      coverPath: '',
      sourceId: '',
      sourceName: '',
      bookUrl: '',
      chapterIndex: Math.max(0, request.chapterIndex),
      pageIndex: Math.max(0, request.pageIndex),
      offset: Math.max(0, request.offset),
      chapterTitle: '',
      chapterCount: 0,
      isCompleteBook: request.mode === ContinuationTransferMode.IMPORT_TO_LIBRARY || request.isLocal,
      ebook: null,
      manga: null,
      novelBook: null,
      novelChapters: [],
      chapterContents: [],
      files: []
    };
    return manifest;
  }

  private async buildEBookPackage(
    request: ContinuationTransferRequest,
    manifest: ContinuationTransferManifest,
    packageDirectory: string,
    sourceBookId: string = request.sourceBookId
  ): Promise<void> {
    const sourceBook = await EBookDataManager.getInstance().getEBookById(sourceBookId);
    if (!sourceBook) {
      throw new Error(`源设备未找到电子书: ${sourceBookId}`);
    }
    manifest.title = sourceBook.metadata.title;
    manifest.author = sourceBook.metadata.author;
    manifest.coverPath = sourceBook.metadata.coverImagePath;
    manifest.chapterCount = sourceBook.chapters.length;
    const fileMap: Map<string, string> = new Map<string, string>();
    let relativeBookFile = '';
    if (sourceBook.filePath.length > 0 && SafeFileUtils.accessSync(sourceBook.filePath)) {
      const fileName = this.getFileName(sourceBook.filePath, 'book.bin');
      relativeBookFile = await this.copySourceFile(sourceBook.filePath, `files/book/${fileName}`, packageDirectory, manifest.files);
      fileMap.set(sourceBook.filePath, relativeBookFile);
    } else if (sourceBook.chapters.length <= 0) {
      throw new Error(`电子书缺少源文件和可读章节: ${sourceBookId}`);
    }

    let extractedRoot = '';
    if (sourceBook.extractedRootPath.length > 0 && SafeFileUtils.accessSync(sourceBook.extractedRootPath)) {
      extractedRoot = 'files/extracted';
      await this.copySourceDirectory(sourceBook.extractedRootPath, extractedRoot, packageDirectory, manifest.files, fileMap);
    }
    if (sourceBook.metadata.coverImagePath.length > 0 &&
      SafeFileUtils.accessSync(sourceBook.metadata.coverImagePath) &&
      !fileMap.has(sourceBook.metadata.coverImagePath)) {
      const coverName = this.getFileName(sourceBook.metadata.coverImagePath, 'cover.img');
      const coverRelativePath = await this.copySourceFile(
        sourceBook.metadata.coverImagePath,
        `files/cover/${coverName}`,
        packageDirectory,
        manifest.files
      );
      fileMap.set(sourceBook.metadata.coverImagePath, coverRelativePath);
    }

    const chapters: EBookChapter[] = [];
    for (let index = 0; index < sourceBook.chapters.length; index++) {
      const sourceChapter = sourceBook.chapters[index];
      const chapter: EBookChapter = {
        id: sourceChapter.id,
        bookId: sourceBookId,
        chapterNumber: sourceChapter.chapterNumber,
        title: sourceChapter.title,
        content: '',
        startPosition: sourceChapter.startPosition,
        endPosition: sourceChapter.endPosition,
        wordCount: sourceChapter.wordCount,
        resourceHref: sourceChapter.resourceHref,
        resourceFile: sourceChapter.resourceFile,
        resourceMediaType: sourceChapter.resourceMediaType,
        resourceLayoutType: sourceChapter.resourceLayoutType,
        resourceImagePath: '',
        resourceImageRelativePath: sourceChapter.resourceImageRelativePath,
        createTime: sourceChapter.createTime
      };
      if (sourceChapter.content.length > 0) {
        const contentPath = `chapters/${index.toString().padStart(6, '0')}.txt`;
        await this.writeText(`${packageDirectory}/${contentPath}`, sourceChapter.content);
        await this.registerFile(contentPath, packageDirectory, manifest.files);
        const contentRecord: ContinuationChapterContent = {
          chapterIndex: index,
          relativePath: contentPath,
          title: sourceChapter.title
        };
        manifest.chapterContents.push(contentRecord);
      }
      const resourcePath = sourceChapter.resourceImagePath || '';
      if (resourcePath.length > 0 && SafeFileUtils.accessSync(resourcePath)) {
        let relativeResourcePath = fileMap.get(resourcePath) || '';
        if (relativeResourcePath.length <= 0) {
          const resourceName = this.getFileName(resourcePath, `resource_${index}.img`);
          relativeResourcePath = await this.copySourceFile(
            resourcePath,
            `files/resources/${index}_${resourceName}`,
            packageDirectory,
            manifest.files
          );
          fileMap.set(resourcePath, relativeResourcePath);
        }
        chapter.resourceImagePath = relativeResourcePath;
      }
      chapters.push(chapter);
    }

    const metadata: EBookMetadata = {
      title: sourceBook.metadata.title,
      author: sourceBook.metadata.author,
      publisher: sourceBook.metadata.publisher,
      publishDate: sourceBook.metadata.publishDate,
      isbn: sourceBook.metadata.isbn,
      language: sourceBook.metadata.language,
      description: sourceBook.metadata.description,
      coverImagePath: fileMap.get(sourceBook.metadata.coverImagePath) || '',
      tags: sourceBook.metadata.tags,
      rating: sourceBook.metadata.rating
    };
    const transferredBook = new EBook(
      sourceBookId,
      sourceBook.format,
      relativeBookFile,
      sourceBook.fileSize,
      metadata,
      chapters,
      sourceBook.status,
      {
        bookId: sourceBookId,
        currentChapterId: sourceBook.chapters[request.chapterIndex]?.id || sourceBook.readingProgress.currentChapterId,
        currentChapterIndex: request.chapterIndex,
        currentPosition: request.offset > 0 ? request.offset : request.pageIndex,
        domPos: `continuation:${request.chapterIndex}:${request.pageIndex}:${request.offset}`,
        progress: sourceBook.readingProgress.progress,
        lastReadTime: Date.now(),
        totalReadingTime: sourceBook.readingProgress.totalReadingTime
      },
      DEFAULT_EBOOK_READING_SETTINGS,
      sourceBook.addTime,
      Date.now(),
      true,
      sourceBook.totalWordCount,
      sourceBook.isPrivate,
      sourceBook.isNSFW
    );
    transferredBook.contentMode = sourceBook.contentMode;
    transferredBook.preferredReaderEngine = sourceBook.preferredReaderEngine;
    transferredBook.extractedRootPath = extractedRoot;
    manifest.ebook = transferredBook;
    manifest.chapterTitle = transferredBook.chapters[request.chapterIndex]?.title || '';
    manifest.isCompleteBook = true;
  }

  private async buildMangaPackage(
    request: ContinuationTransferRequest,
    manifest: ContinuationTransferManifest,
    packageDirectory: string,
    initialBundle: MangaTransferBundle,
    mangaBundleProvider: MangaBundleProvider
  ): Promise<void> {
    let sourceBundle = initialBundle;
    if (!request.isLocal) {
      await this.ensureOnlineMangaPayload(request, sourceBundle);
      const refreshedBundle = await mangaBundleProvider();
      if (!refreshedBundle) {
        throw new Error('在线漫画下载后无法重新读取完整数据');
      }
      sourceBundle = refreshedBundle;
    }
    const bundle = this.cloneMangaBundle(sourceBundle);
    const isCurrentChapterOnly = !request.isLocal && request.mode === ContinuationTransferMode.READ_ONLY;
    let currentChapterId = '';
    if (isCurrentChapterOnly) {
      for (const chapter of bundle.chapters) {
        if (chapter.index === request.chapterIndex) {
          currentChapterId = chapter.id;
          manifest.chapterTitle = chapter.title;
          break;
        }
      }
      if (currentChapterId.length <= 0) {
        throw new Error(`源端未找到当前漫画章节: index=${request.chapterIndex}`);
      }
      bundle.chapterPages = bundle.chapterPages.filter((chapterPages) => chapterPages.chapterId === currentChapterId);
    }

    const originalPathMap: Map<string, string> = new Map<string, string>();
    const transferredFiles: MangaTransferFileEntry[] = [];
    for (const file of sourceBundle.files) {
      if (isCurrentChapterOnly && !file.relPath.startsWith(`chapter_${currentChapterId}`) && !file.relPath.startsWith('cover/')) {
        continue;
      }
      const targetRelativePath = `files/manga/${this.normalizeRelativePath(file.relPath)}`;
      const actualRelativePath = await this.copySourceFile(
        file.originalPath,
        targetRelativePath,
        packageDirectory,
        manifest.files
      );
      originalPathMap.set(file.originalPath, actualRelativePath);
      const transferredFile: MangaTransferFileEntry = {
        originalPath: '',
        relPath: actualRelativePath,
        size: file.size,
        hash: file.hash
      };
      transferredFiles.push(transferredFile);
    }
    for (const chapterPageGroup of bundle.chapterPages) {
      for (const page of chapterPageGroup.pages) {
        if (page.localPath.length > 0) {
          page.localPath = originalPathMap.get(page.localPath) || '';
        }
      }
    }
    const sourceCoverPath = bundle.comic.coverLocalPath.length > 0
      ? bundle.comic.coverLocalPath
      : bundle.comic.coverUrl;
    const mappedCoverPath = originalPathMap.get(sourceCoverPath) || '';
    if (mappedCoverPath.length > 0) {
      bundle.comic.coverLocalPath = mappedCoverPath;
      if (bundle.comic.coverUrl === sourceCoverPath) {
        bundle.comic.coverUrl = '';
      }
    } else if (bundle.comic.coverLocalPath.length > 0) {
      bundle.comic.coverLocalPath = '';
    }
    for (const chapter of bundle.chapters) {
      chapter.downloadPath = '';
    }
    bundle.files = transferredFiles;

    if (request.mode === ContinuationTransferMode.IMPORT_TO_LIBRARY && !request.isLocal) {
      for (const group of bundle.chapterPages) {
        for (const page of group.pages) {
          if (page.imageUrl.length > 0 && page.localPath.length <= 0) {
            throw new Error(`在线漫画缺少已下载页面，无法完整导入: chapter=${group.chapterId}, page=${page.index + 1}`);
          }
        }
      }
    }
    manifest.title = bundle.comic.title;
    manifest.author = bundle.comic.author;
    manifest.coverPath = bundle.comic.coverLocalPath;
    manifest.sourceId = bundle.comic.sourceId;
    manifest.chapterCount = sourceBundle.chapters.length;
    manifest.manga = bundle;
    manifest.isCompleteBook = !isCurrentChapterOnly;
  }

  private async ensureOnlineMangaPayload(
    request: ContinuationTransferRequest,
    bundle: MangaTransferBundle
  ): Promise<void> {
    const sourceId = Number(bundle.comic.sourceId);
    if (!Number.isFinite(sourceId) || sourceId <= 0) {
      throw new Error(`在线漫画缺少有效图源 ID: ${bundle.comic.sourceId}`);
    }
    const selectedChapters = request.mode === ContinuationTransferMode.READ_ONLY
      ? bundle.chapters.filter((chapter) => chapter.index === request.chapterIndex)
      : bundle.chapters;
    if (selectedChapters.length <= 0) {
      throw new Error('在线漫画没有可传输的章节列表');
    }
    const downloadManager = getUnifiedDownloadManager();
    for (const chapter of selectedChapters) {
      const pageGroup = bundle.chapterPages.find((group) => group.chapterId === chapter.id);
      if (!pageGroup || pageGroup.pages.length <= 0) {
        throw new Error(`在线漫画缺少章节图片列表: ${chapter.title}`);
      }
      const hasUncachedPage = pageGroup.pages.some(
        (page) => page.localPath.length <= 0 && page.imageUrl.length > 0
      );
      if (!hasUncachedPage) {
        continue;
      }
      const imageUrls: string[] = pageGroup.pages
        .filter((page) => page.imageUrl.length > 0)
        .map((page) => page.imageUrl);
      const downloadParams: MangaChapterDownloadParams = {
        mangaId: request.sourceBookId,
        mangaTitle: bundle.comic.title,
        chapterId: chapter.id,
        chapterTitle: chapter.title,
        chapterIndex: chapter.index,
        sourceId: sourceId,
        imageUrls: imageUrls
      };
      const taskId = await downloadManager.downloadMangaChapter(downloadParams);
      if (!(await this.waitForMangaDownload(downloadManager, taskId))) {
        throw new Error(`在线漫画章节下载失败: ${chapter.title}`);
      }
    }
  }

  private async waitForMangaDownload(downloadManager: UnifiedDownloadManager, taskId: string): Promise<boolean> {
    const maxAttempts = 3600;
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      const task = downloadManager.getTask(taskId);
      if (!task) {
        return false;
      }
      if (task.status === UnifiedTaskStatus.COMPLETED) {
        return true;
      }
      if (task.status === UnifiedTaskStatus.FAILED) {
        return false;
      }
      await new Promise<void>((resolve) => {
        setTimeout(() => resolve(), 500);
      });
    }
    return false;
  }

  private async buildNovelPackage(
    request: ContinuationTransferRequest,
    manifest: ContinuationTransferManifest,
    packageDirectory: string
  ): Promise<void> {
    if (request.isLocal && request.sourceBookId.startsWith('local_txt_ebook_')) {
      const ebookId = getLocalTextNovelEBookId(request.sourceBookId);
      if (ebookId.length <= 0) {
        throw new Error(`本地 TXT 小说 ID 无效: ${request.sourceBookId}`);
      }
      await this.buildEBookPackage(request, manifest, packageDirectory, ebookId);
      const ebook = manifest.ebook;
      if (!ebook) {
        throw new Error('本地 TXT 小说电子书数据缺失');
      }
      const now = Date.now();
      manifest.sourceId = LOCAL_TXT_NOVEL_SOURCE_ID;
      manifest.bookUrl = `ebook://${ebookId}`;
      manifest.novelBook = {
        id: request.sourceBookId,
        sourceId: LOCAL_TXT_NOVEL_SOURCE_ID,
        sourceName: '本地电子书',
        bookUrl: manifest.bookUrl,
        name: ebook.metadata.title,
        author: ebook.metadata.author,
        coverUrl: ebook.metadata.coverImagePath,
        coverLocalPath: ebook.metadata.coverImagePath,
        chapterCount: ebook.chapters.length,
        readStatus: NovelReadStatus.READING,
        lastReadChapterId: ebook.chapters[request.chapterIndex]?.id || '',
        lastReadChapterIndex: request.chapterIndex,
        lastReadPosition: request.offset,
        lastReadTime: now,
        totalReadingTime: ebook.readingProgress.totalReadingTime * 60,
        isFavorite: false,
        createTime: ebook.addTime,
        updateDbTime: now
      };
      manifest.novelChapters = ebook.chapters.map((chapter: EBookChapter, index: number): NovelChapter => ({
        id: chapter.id || `${request.sourceBookId}_${index}`,
        bookId: request.sourceBookId,
        url: `ebook://${ebookId}/chapter/${index}`,
        title: chapter.title,
        index: index,
        isVolume: false,
        isVip: false,
        isPay: false,
        isDownloaded: true,
        contentPath: '',
        wordCount: chapter.wordCount,
        updateTime: chapter.createTime,
        createTime: chapter.createTime
      }));
      manifest.chapterCount = ebook.chapters.length;
      manifest.isCompleteBook = true;
      manifest.title = ebook.metadata.title;
      manifest.author = ebook.metadata.author;
      manifest.coverPath = ebook.metadata.coverImagePath;
      manifest.chapterTitle = ebook.chapters[request.chapterIndex]?.title || '';
      return;
    }
    const dataManager = getNovelDataManager();
    const book = await dataManager.getBook(request.sourceBookId);
    if (!book) {
      throw new Error(`源设备未找到小说元数据: ${request.sourceBookId}`);
    }
    const cacheManager = getNovelChapterCacheManager();
    const chapters = await cacheManager.getCachedChapterList(book.id, 876000);
    if (!chapters || chapters.length <= 0) {
      throw new Error(`源设备没有可传输的小说目录: ${book.name}`);
    }
    const selectedIndexes: number[] = [];
    if (request.mode === ContinuationTransferMode.READ_ONLY) {
      selectedIndexes.push(Math.max(0, Math.min(request.chapterIndex, chapters.length - 1)));
    } else {
      for (let index = 0; index < chapters.length; index++) {
        selectedIndexes.push(index);
      }
    }
    const chapterContents: ContinuationChapterContent[] = [];
    const novelChapters: NovelChapter[] = [];
    let currentChapterTitle = '';
    for (const chapter of chapters) {
      const novelChapter: NovelChapter = {
        id: chapter.id || `${book.id}_${chapter.index}`,
        bookId: book.id,
        url: chapter.url,
        title: chapter.title,
        index: chapter.index,
        isVolume: chapter.isVolume === true,
        isVip: chapter.isVip === true,
        isPay: chapter.isPay === true,
        isDownloaded: true,
        contentPath: '',
        wordCount: 0,
        updateTime: chapter.updateTime,
        createTime: Date.now()
      };
      novelChapters.push(novelChapter);
    }
    for (const chapterIndex of selectedIndexes) {
      const chapter = chapters.find((item: LegadoChapter): boolean => item.index === chapterIndex);
      if (!chapter) {
        throw new Error(`小说目录缺少章节索引: ${chapterIndex}`);
      }
      let content = await cacheManager.getChapterCache(book.id, chapterIndex);
      if (!content || content.length <= 0) {
        const cached = await cacheManager.cacheChapter(book.sourceId, book.id, chapter);
        if (cached) {
          content = await cacheManager.getChapterCache(book.id, chapterIndex);
        }
      }
      if (!content || content.length <= 0) {
        throw new Error(`小说章节内容不可用: ${chapter.title}`);
      }
      const relativePath = `chapters/${chapterIndex.toString().padStart(6, '0')}.txt`;
      await this.writeText(`${packageDirectory}/${relativePath}`, content);
      await this.registerFile(relativePath, packageDirectory, manifest.files);
      chapterContents.push({ chapterIndex: chapterIndex, relativePath: relativePath, title: chapter.title });
      if (chapterIndex === request.chapterIndex) {
        currentChapterTitle = chapter.title;
      }
    }
    manifest.title = book.name;
    manifest.author = book.author;
    manifest.coverPath = book.coverLocalPath || book.coverUrl || '';
    manifest.sourceId = book.sourceId;
    manifest.sourceName = book.sourceName;
    manifest.bookUrl = book.bookUrl;
    manifest.chapterTitle = currentChapterTitle;
    manifest.chapterCount = chapters.length;
    manifest.novelBook = book;
    manifest.novelChapters = novelChapters;
    manifest.chapterContents = chapterContents;
    manifest.isCompleteBook = request.mode === ContinuationTransferMode.IMPORT_TO_LIBRARY;
  }

  private cloneMangaBundle(bundle: MangaTransferBundle): MangaTransferBundle {
    return {
      comic: {
        id: bundle.comic.id,
        title: bundle.comic.title,
        author: bundle.comic.author,
        description: bundle.comic.description,
        coverUrl: bundle.comic.coverUrl,
        coverLocalPath: bundle.comic.coverLocalPath,
        sourceId: bundle.comic.sourceId,
        externalId: bundle.comic.externalId,
        status: bundle.comic.status,
        tags: bundle.comic.tags.slice(),
        rating: bundle.comic.rating,
        chapterCount: bundle.comic.chapterCount,
        lastUpdateTime: bundle.comic.lastUpdateTime,
        addTime: bundle.comic.addTime,
        contentType: bundle.comic.contentType,
        isNSFW: bundle.comic.isNSFW,
        isPrivate: bundle.comic.isPrivate
      },
      chapters: bundle.chapters.map((chapter): RemoteChapterMetadata => ({
        id: chapter.id,
        title: chapter.title,
        index: chapter.index,
        pageCount: chapter.pageCount,
        isDownloaded: chapter.isDownloaded,
        downloadPath: chapter.downloadPath,
        publishTime: chapter.publishTime,
        addTime: chapter.addTime,
        externalId: chapter.externalId
      })),
      chapterPages: bundle.chapterPages.map((group): MangaChapterPagesEntry => ({
        chapterId: group.chapterId,
        pages: group.pages.map((page): RemotePageMetadata => ({
          id: page.id,
          index: page.index,
          imageUrl: page.imageUrl,
          localPath: page.localPath,
          width: page.width,
          height: page.height,
          fileSize: page.fileSize
        }))
      })),
      files: bundle.files.map((file): MangaTransferFileEntry => ({
        originalPath: file.originalPath,
        relPath: file.relPath,
        size: file.size,
        hash: file.hash
      }))
    };
  }

  private async copySourceDirectory(
    sourceDirectory: string,
    relativeDirectory: string,
    packageDirectory: string,
    files: ContinuationTransferFile[],
    fileMap: Map<string, string>
  ): Promise<void> {
    for (const name of SafeFileUtils.listFileSync(sourceDirectory)) {
      const sourcePath = `${sourceDirectory}/${name}`;
      const stat = SafeFileUtils.lstatSyncStrict(sourcePath);
      const relativePath = `${relativeDirectory}/${name}`;
      if (stat.isDirectory()) {
        await this.copySourceDirectory(sourcePath, relativePath, packageDirectory, files, fileMap);
      } else {
        await this.copySourceFile(sourcePath, relativePath, packageDirectory, files);
        fileMap.set(sourcePath, relativePath);
      }
    }
  }

  private async copySourceFile(
    sourcePath: string,
    relativePath: string,
    packageDirectory: string,
    files: ContinuationTransferFile[]
  ): Promise<string> {
    if (!SafeFileUtils.accessSync(sourcePath)) {
      throw new Error(`接续依赖文件不存在: ${sourcePath}`);
    }
    const safeRelativePath = this.normalizeRelativePath(relativePath);
    const targetPath = `${packageDirectory}/${safeRelativePath}`;
    this.ensureParentDirectory(targetPath);
    SafeFileUtils.copyFileSyncStrict(sourcePath, targetPath);
    await this.registerFile(safeRelativePath, packageDirectory, files);
    return safeRelativePath;
  }

  private async registerFile(
    relativePath: string,
    packageDirectory: string,
    files: ContinuationTransferFile[]
  ): Promise<void> {
    const safeRelativePath = this.normalizeRelativePath(relativePath);
    const targetPath = `${packageDirectory}/${safeRelativePath}`;
    const stat = SafeFileUtils.statSyncStrict(targetPath);
    const file: ContinuationTransferFile = {
      name: this.getFileName(safeRelativePath, 'data.bin'),
      relativePath: safeRelativePath,
      sourcePath: '',
      size: stat.size,
      sha256: await this.computeFileHash(targetPath)
    };
    if (file.sha256.length <= 0) {
      throw new Error(`计算接续文件哈希失败: ${safeRelativePath}`);
    }
    files.push(file);
  }

  private async computeFileHash(filePath: string): Promise<string> {
    const file = SafeFileUtils.openSyncStrict(filePath, fileIo.OpenMode.READ_ONLY);
    const digest = cryptoFramework.createMd('SHA256');
    const buffer = new ArrayBuffer(FILE_HASH_CHUNK_SIZE);
    try {
      let readBytes = 0;
      while ((readBytes = SafeFileUtils.readSyncStrict(file.fd, buffer)) > 0) {
        await digest.update({ data: new Uint8Array(buffer.slice(0, readBytes)) } as cryptoFramework.DataBlob);
      }
      const result = await digest.digest();
      return bytesToHex(new Uint8Array(result.data));
    } finally {
      SafeFileUtils.closeSync(file);
    }
  }

  private async writeText(path: string, text: string): Promise<void> {
    this.ensureParentDirectory(path);
    const file = SafeFileUtils.openSyncStrict(
      path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
    );
    try {
      SafeFileUtils.writeStringExactSync(file.fd, text);
    } finally {
      SafeFileUtils.closeSync(file);
    }
  }

  private writeJson(path: string, value: Object): void {
    this.ensureParentDirectory(path);
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

  private ensureParentDirectory(path: string): void {
    const lastSlash = path.lastIndexOf('/');
    if (lastSlash > 0) {
      const parentPath = path.substring(0, lastSlash);
      if (SafeFileUtils.accessSync(parentPath)) {
        if (!SafeFileUtils.lstatSyncStrict(parentPath).isDirectory()) {
          throw new Error(`接续数据包父路径不是目录: ${parentPath}`);
        }
        return;
      }
      try {
        SafeFileUtils.mkdirSyncStrict(parentPath, true);
      } catch (error) {
        if (SafeFileUtils.accessSync(parentPath) && SafeFileUtils.lstatSyncStrict(parentPath).isDirectory()) {
          return;
        }
        throw error as Error;
      }
      if (!SafeFileUtils.lstatSyncStrict(parentPath).isDirectory()) {
        throw new Error(`接续数据包父路径创建失败: ${parentPath}`);
      }
    }
  }

  private normalizeRelativePath(path: string): string {
    const normalized = path.replace(/\\/g, '/').replace(/^\/+/, '');
    const segments = normalized.split('/');
    const safeSegments: string[] = [];
    for (const segment of segments) {
      if (segment.length <= 0 || segment === '.' || segment === '..') {
        continue;
      }
      safeSegments.push(segment.replace(/[^A-Za-z0-9._-]/g, '_'));
    }
    return safeSegments.join('/');
  }

  private getFileName(path: string, fallback: string): string {
    const normalized = path.replace(/\\/g, '/');
    const name = normalized.substring(normalized.lastIndexOf('/') + 1);
    return name.length > 0 ? name.replace(/[^A-Za-z0-9._-]/g, '_') : fallback;
  }

  private sanitizeSegment(value: string): string {
    const safe = value.replace(/[^A-Za-z0-9_-]/g, '_');
    return safe.length > 0 ? safe : 'empty';
  }

  private deleteDirectoryIfPresent(path: string): void {
    if (!SafeFileUtils.accessSync(path)) {
      return;
    }
    const stat = SafeFileUtils.lstatSyncStrict(path);
    if (!stat.isDirectory()) {
      SafeFileUtils.unlinkSyncStrict(path);
      return;
    }
    for (const entry of SafeFileUtils.listFileSync(path)) {
      this.deleteDirectoryIfPresent(`${path}/${entry}`);
    }
    SafeFileUtils.rmdirSync(path);
  }
}
