import { SafeFileUtils } from '../../Utils/SafeFileUtils';
import { fileIo as fs } from '@kit.CoreFileKit';
import { EBook } from '../../Models/EBookModels';
import { logger } from '../../Utils/Logger';
import { EBookDataManager } from '../Data/EBookDataManager';
import { EBookCoverExtractor, EBookParserFactory } from '../Parsers/EBookParser';
import { getContext } from '../../GlobalContext';

const TAG = 'OnlineEBookImportService';

export class OnlineEBookImportService {
  private static instance: OnlineEBookImportService;
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();

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
    // [修复] ReaderKit 解析失败会走降级解析：标题回退为文件名（即 targetBookId）、无真实章节。
    // 对传输导入而言这等同于“文件损坏/不完整”，不能入库，否则目标端后续打开会报
    // “File is not exist / 加载章节失败”，且残留记录会让下次接续跳过重新拉取。
    const parsedTitle = (ebook.metadata.title || '').trim();
    if (parsedTitle.length <= 0 || parsedTitle === targetBookId) {
      throw new Error(`传输文件解析异常，文件可能不完整: ${finalPath}`);
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
}
