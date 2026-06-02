import { SafeFileUtils } from '../../Utils/SafeFileUtils';
import { fileIo as fs } from '@kit.CoreFileKit';
import { EBook } from '../../Models/EBookModels';
import { logger } from '../../Utils/Logger';
import { EBookDataManager } from '../Data/EBookDataManager';
import { EBookCoverExtractor, EBookParserFactory } from '../Parsers/EBookParser';

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
}
