import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { fileIo as fs } from '@kit.CoreFileKit';
import { EBook, EBookFormat } from 'manxia_core/src/main/ets/Models/EBookModels';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { EBookDataManager } from 'manxia_core/src/main/ets/Framework/Data/EBookDataManager';
import { EBookCoverExtractor, EBookParserFactory } from '../Parsers/EBookParser';
import { TransferredBookValidation } from './TransferredBookValidation';
import { getContext } from 'manxia_core/src/main/ets/GlobalContext';
import { ContinuationCacheManager } from '../Distributed/ContinuationCacheManager';
import { ContinuationTransferManifest } from '../Distributed/ContinuationReadingTypes';

const TAG = 'OnlineEBookImportService';

export class OnlineEBookImportService {
  private static instance: OnlineEBookImportService;
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private transferredBookValidation: TransferredBookValidation = new TransferredBookValidation();

  private constructor() {
  }

  public static getInstance(): OnlineEBookImportService {
    if (!OnlineEBookImportService.instance) {
      OnlineEBookImportService.instance = new OnlineEBookImportService();
    }
    return OnlineEBookImportService.instance;
  }

  public async importDownloadedBook(filePath: string): Promise<EBook> {
    const normalizedFilePath: string = filePath.trim();
    if (normalizedFilePath.length <= 0) {
      throw new Error('下载文件路径为空');
    }

    if (!this.fileExists(normalizedFilePath)) {
      throw new Error(`下载文件不存在: ${normalizedFilePath}`);
    }

    const existingBook: EBook | null = await this.ebookDataManager.getEBookByFilePath(normalizedFilePath);
    if (existingBook) {
      logger.info(TAG, `检测到已导入电子书，直接复用: ${existingBook.id}`);
      return existingBook;
    }

    const parser = EBookParserFactory.createParser(normalizedFilePath);
    if (!parser) {
      throw new Error(`不支持的电子书格式: ${normalizedFilePath}`);
    }

    const ebook: EBook = await parser.parse();
    ebook.isFavorite = true;
    this.normalizeImportedTitle(ebook);

    const folderPath: string = this.getParentDirectory(normalizedFilePath);
    await this.ensureCoverInBookFolder(ebook, normalizedFilePath, folderPath);

    await this.ebookDataManager.saveEBook(ebook);
    logger.info(TAG, `远程电子书导入成功: bookId=${ebook.id}, title=${ebook.metadata.title}`);
    return ebook;
  }

  private normalizeImportedTitle(ebook: EBook): void {
    const title: string = ebook.metadata.title || '';
    if (!title.match(/^\d+_/)) {
      return;
    }

    const cleanTitle = title
      .replace(/^\d+_/, '')
      .replace(/\.(txt|epub|mobi|azw|azw3|pdf)$/i, '')
      .replace(/_[a-f0-9]{6,}$/i, '');
    if (cleanTitle.length > 0) {
      ebook.metadata.title = cleanTitle;
      logger.info(TAG, `已清理远程导入标题: ${cleanTitle}`);
    }
  }

  private async ensureCoverInBookFolder(ebook: EBook, filePath: string, folderPath: string): Promise<void> {
    let coverSaved: boolean = false;

    const originalCoverPath: string = ebook.metadata.coverImagePath || '';
    if (originalCoverPath.length > 0 && this.fileExists(originalCoverPath)) {
      try {
        const coverExt: string = this.getFileExtension(originalCoverPath, '.jpg');
        const targetCoverPath: string = `${folderPath}/cover${coverExt}`;
        if (this.normalizePath(originalCoverPath) !== this.normalizePath(targetCoverPath)) {
          SafeFileUtils.copyFileSync(originalCoverPath, targetCoverPath);
        }
        ebook.metadata.coverImagePath = targetCoverPath;
        coverSaved = true;
        logger.info(TAG, `已复用解析器封面: ${targetCoverPath}`);
      } catch (error) {
        logger.warn(TAG, `复制解析器封面失败: ${String(error)}`);
      }
    }

    if (!coverSaved) {
      try {
        const extractResult = await EBookCoverExtractor.extractCover(filePath, folderPath);
        if (extractResult.success && extractResult.coverPath) {
          ebook.metadata.coverImagePath = extractResult.coverPath;
          coverSaved = true;
          logger.info(TAG, `已提取远程电子书封面: ${extractResult.coverPath}`);
        }
      } catch (error) {
        logger.warn(TAG, `提取远程电子书封面失败: ${String(error)}`);
      }
    }

    if (!coverSaved) {
      logger.info(TAG, `远程电子书未找到可用封面，继续导入: ${ebook.metadata.title}`);
    }
  }

  private fileExists(filePath: string): boolean {
    try {
      return SafeFileUtils.accessSync(filePath);
    } catch (_error) {
      return false;
    }
  }

  private getParentDirectory(filePath: string): string {
    const lastSlashIndex: number = filePath.lastIndexOf('/');
    if (lastSlashIndex <= 0) {
      return filePath;
    }
    return filePath.substring(0, lastSlashIndex);
  }

  private getFileExtension(filePath: string, fallbackExt: string): string {
    const lastSlashIndex: number = filePath.lastIndexOf('/');
    const lastDotIndex: number = filePath.lastIndexOf('.');
    if (lastDotIndex > lastSlashIndex) {
      return filePath.substring(lastDotIndex);
    }
    return fallbackExt;
  }

  private normalizePath(filePath: string): string {
    return filePath.replace(/\\/g, '/').toLowerCase();
  }

  /**
   * [跨端接续] 导入经独立连接通道传输过来的本地书籍文件，并保留源端 bookId：
   * 1. 先把临时文件复制到应用电子书目录（解析器的提取目录与文件同层，必须先落位再解析）；
   * 2. 解析并重绑 bookId（含章节与阅读进度），保证目标端按源端 bookId 命中接续。
   * @param tempFilePath 通道接收到的临时文件路径（使用后可删除）
   * @param targetBookId 源端书籍 ID
   * @param originalFileName 源端原文件名（用于确定扩展名；临时文件统一以 .part 结尾）
   */
  public async importTransferredBook(tempFilePath: string, targetBookId: string, originalFileName: string = ''): Promise<EBook> {
    if (!this.fileExists(tempFilePath)) {
      throw new Error(`传输文件不存在: ${tempFilePath}`);
    }
    if (targetBookId.length <= 0) {
      throw new Error('目标书籍ID为空');
    }

    let ebookRootDir = '';
    try {
      ebookRootDir = `${getContext().filesDir}/ebooks`;
    } catch (error) {
      logger.warn(TAG, `获取应用电子书目录失败: ${String(error)}`);
      ebookRootDir = this.getParentDirectory(tempFilePath);
    }
    const extension = originalFileName.length > 0
      ? this.getFileExtension(originalFileName, '.epub')
      : this.getFileExtension(tempFilePath, '.epub');
    const bookDir = `${ebookRootDir}/transferred_${targetBookId}`;
    // [修复] 目录可能已存在（此前接续已同步过）：mkdirSync 对已存在目录会抛 EEXIST，先探测再创建
    if (!SafeFileUtils.accessSync(bookDir)) {
      SafeFileUtils.mkdirSync(bookDir, true);
    }
    const finalPath = `${bookDir}/${targetBookId}${extension}`;
    try {
      SafeFileUtils.copyFileSync(tempFilePath, finalPath);
    } catch (error) {
      logger.warn(TAG, `复制传输文件失败: ${String(error)}`);
    }
    if (!this.fileExists(finalPath)) {
      throw new Error(`复制传输文件失败: ${finalPath}`);
    }
    // [修复] 复制后校验大小一致，防止残留旧文件/复制不完整被当成成功导入
    const srcSize = SafeFileUtils.statSync(tempFilePath).size;
    const dstSize = SafeFileUtils.statSync(finalPath).size;
    if (srcSize <= 0 || dstSize !== srcSize) {
      throw new Error(`复制传输文件大小不一致: src=${srcSize}, dst=${dstSize}`);
    }

    const parser = EBookParserFactory.createParser(finalPath);
    if (!parser) {
      throw new Error(`不支持的电子书格式: ${finalPath}`);
    }

    const ebook: EBook = await parser.parse();
    // ReaderKit 降级结果以 bookId 为标题时视为无效；有效 PDF 则用解析出的页面章节证明内容完整。
    const parsedTitle = (ebook.metadata.title || '').trim();
    if (parsedTitle.length <= 0 || parsedTitle === targetBookId) {
      if (ebook.format === EBookFormat.PDF && this.transferredBookValidation.hasUsablePdfPages(ebook)) {
        ebook.metadata.title = this.transferredBookValidation.getPdfFallbackTitle(originalFileName, targetBookId);
        logger.warn(TAG, `接续PDF没有文档标题元数据，已使用文件名: bookId=${targetBookId}, title=${ebook.metadata.title}, pages=${ebook.chapters.length}`);
      } else {
        throw new Error(`传输文件解析异常，缺少有效标题或内容: ${finalPath}`);
      }
    }
    // 重绑为源端 bookId（接续按 bookId 命中；章节与阅读进度同步重绑）
    ebook.id = targetBookId;
    for (const chapter of ebook.chapters) {
      chapter.bookId = targetBookId;
    }
    if (ebook.readingProgress) {
      ebook.readingProgress.bookId = targetBookId;
    }
    this.normalizeImportedTitle(ebook);
    await this.ensureCoverInBookFolder(ebook, finalPath, bookDir);
    await this.ebookDataManager.saveEBook(ebook);
    logger.info(TAG, `接续传输电子书导入成功: bookId=${targetBookId}, title=${ebook.metadata.title}`);
    return ebook;
  }

  public async importContinuationPackage(
    manifest: ContinuationTransferManifest,
    packageDirectory: string
  ): Promise<EBook> {
    if (manifest.schemaVersion !== 1 || !manifest.ebook ||
      (manifest.contentType !== 'ebook' && !(manifest.contentType === 'novel' && manifest.isLocal))) {
      throw new Error('接续电子书数据包格式无效');
    }
    const targetBookId = manifest.contentType === 'novel' && manifest.isLocal
      ? manifest.ebook.id
      : manifest.sourceBookId;
    const context = getContext();
    const ebookRoot = `${context.filesDir}/ebooks`;
    const safeBookId = targetBookId.replace(/[^A-Za-z0-9_-]/g, '_');
    const stageDirectory = `${ebookRoot}/.continuation_pending_${safeBookId}_${Date.now()}`;
    const finalDirectory = `${ebookRoot}/continuation_${safeBookId}_${Date.now()}`;
    let movedToFinal = false;
    const previousBook = await this.ebookDataManager.getEBookById(targetBookId);
    try {
      SafeFileUtils.mkdirSync(stageDirectory, true);
      for (const file of manifest.files) {
        const relativePath = this.normalizePackagePath(file.relativePath);
        const sourcePath = `${packageDirectory}/${relativePath}`;
        const targetPath = `${stageDirectory}/${relativePath}`;
        if (!SafeFileUtils.accessSync(sourcePath)) {
          throw new Error(`接续电子书文件缺失: ${relativePath}`);
        }
        this.ensureDirectory(targetPath.substring(0, targetPath.lastIndexOf('/')));
        SafeFileUtils.copyFileSyncStrict(sourcePath, targetPath);
      }
      // materializeEBook resolves paths in place on the shared manifest metadata objects.
      const relativeFilePath = manifest.ebook.filePath;
      const relativeExtractedRoot = manifest.ebook.extractedRootPath;
      const relativeCoverPath = manifest.ebook.metadata.coverImagePath;
      const relativeChapterPaths: string[] = [];
      for (const chapter of manifest.ebook.chapters) {
        relativeChapterPaths.push(chapter.resourceImagePath || '');
      }
      const cacheManager = ContinuationCacheManager.getInstance();
      const stagedBook = cacheManager.materializeEBook(manifest, stageDirectory, targetBookId);
      if (!stagedBook) {
        throw new Error('接续电子书元数据不完整');
      }
      SafeFileUtils.renameSyncStrict(stageDirectory, finalDirectory);
      movedToFinal = true;
      stagedBook.filePath = this.resolvePackagePath(finalDirectory, relativeFilePath);
      stagedBook.extractedRootPath = this.resolvePackagePath(finalDirectory, relativeExtractedRoot);
      stagedBook.metadata.coverImagePath = this.resolvePackagePath(finalDirectory, relativeCoverPath);
      for (let index = 0; index < stagedBook.chapters.length; index++) {
        stagedBook.chapters[index].resourceImagePath = this.resolvePackagePath(
          finalDirectory,
          relativeChapterPaths[index]
        );
      }
      stagedBook.isFavorite = true;
      stagedBook.lastUpdateTime = Date.now();
      stagedBook.readingProgress.currentChapterIndex = manifest.chapterIndex;
      stagedBook.readingProgress.currentPosition = manifest.offset > 0 ? manifest.offset : manifest.pageIndex;
      stagedBook.readingProgress.lastReadTime = Date.now();
      stagedBook.readingProgress.bookId = targetBookId;
      await this.ebookDataManager.saveEBook(stagedBook, { skipReadingSettings: true });
      logger.info(TAG, `完整接续电子书已导入书库: bookId=${targetBookId}, title=${stagedBook.metadata.title}`);
      return stagedBook;
    } catch (error) {
      if (previousBook) {
        try {
          await this.ebookDataManager.saveEBook(previousBook, { skipReadingSettings: true });
        } catch (restoreError) {
          logger.error(TAG, `接续导入失败后恢复原电子书记录失败: ${String(restoreError)}`);
        }
      } else {
        try {
          await this.ebookDataManager.deleteEBook(targetBookId);
        } catch (deleteError) {
          logger.warn(TAG, `接续导入失败后清理电子书记录失败: ${String(deleteError)}`);
        }
      }
      if (movedToFinal) {
        this.deleteDirectory(finalDirectory);
      } else {
        this.deleteDirectory(stageDirectory);
      }
      throw error as Error;
    }
  }

  private normalizePackagePath(path: string): string {
    const normalized = path.replace(/\\/g, '/');
    if (normalized.startsWith('/') || normalized.indexOf(':') >= 0) {
      throw new Error('接续电子书路径包含绝对路径');
    }
    const segments = normalized.split('/');
    for (const segment of segments) {
      if (segment === '..') {
        throw new Error('接续电子书路径越界');
      }
    }
    return normalized;
  }

  private resolvePackagePath(root: string, relativePath: string): string {
    const normalized = this.normalizePackagePath(relativePath);
    if (normalized.length <= 0) {
      return '';
    }
    return `${root}/${normalized}`;
  }

  private ensureDirectory(path: string): void {
    if (SafeFileUtils.accessSync(path)) {
      if (!SafeFileUtils.lstatSyncStrict(path).isDirectory()) {
        throw new Error(`接续电子书目标路径不是目录: ${path}`);
      }
      return;
    }
    try {
      SafeFileUtils.mkdirSyncStrict(path, true);
    } catch (error) {
      if (SafeFileUtils.accessSync(path) && SafeFileUtils.lstatSyncStrict(path).isDirectory()) {
        return;
      }
      throw error as Error;
    }
    if (!SafeFileUtils.lstatSyncStrict(path).isDirectory()) {
      throw new Error(`接续电子书目标目录创建失败: ${path}`);
    }
  }

  private deleteDirectory(path: string): void {
    if (!SafeFileUtils.accessSync(path)) {
      return;
    }
    const stat = SafeFileUtils.lstatSyncStrict(path);
    if (!stat.isDirectory()) {
      SafeFileUtils.unlinkSyncStrict(path);
      return;
    }
    for (const entry of SafeFileUtils.listFileSync(path)) {
      this.deleteDirectory(`${path}/${entry}`);
    }
    SafeFileUtils.rmdirSync(path);
  }
}
