import { SafeFileUtils } from '../../Utils/SafeFileUtils';
// 文件路径: entry/src/main/ets/Framework/Parsers/ReaderKitParser.ets
/**
 * Reader Kit 电子书解析器
 * 使用 HarmonyOS 官方 Reader Kit 解析 EPUB、MOBI、AZW 等格式
 * 
 * 注意：Reader Kit 支持格式：TXT、EPUB、MOBI、AZW、AZW3
 *      不支持 PDF 格式
 */

import { EBook, EBookFormat, EBookMetadata, EBookChapter, EBookStatus } from '../../Models/EBookModels';
import { logger } from '../../Utils/Logger';
import { fileIo } from '@kit.CoreFileKit';
import { isReaderKitEnabled } from '../Initialization/ReaderKitFeatureGate';
import { bookParser } from '@kit.ReaderKit';
 

const TAG = 'ReaderKitParser';

async function createReaderKitBookParserHandler(filePath: string): Promise<bookParser.BookParserHandler> {
  if (!isReaderKitEnabled()) {
    throw new Error('Reader Kit is unavailable in current environment');
  }
  return await bookParser.getDefaultHandler(filePath);
}

/**
 * Reader Kit 电子书解析器
 * 使用官方 Reader Kit API 解析支持的格式
 */
export class ReaderKitEBookParser {
  private filePath: string;
  private format: EBookFormat;

  constructor(filePath: string, format: EBookFormat) {
    this.filePath = filePath;
    this.format = format;
  }

  /**
   * 检查 Reader Kit 是否支持该格式
   */
  public static isSupportedFormat(format: EBookFormat): boolean {
    const supportedFormats = [
      EBookFormat.TXT,
      EBookFormat.EPUB,
      EBookFormat.MOBI,
      EBookFormat.AZW,
      EBookFormat.AZW3
    ];
    return supportedFormats.includes(format);
  }

  /**
   * 解析电子书
   * 注意：由于 Reader Kit API 在官方文档中信息有限，此处提供基础框架
   * 实际使用时需要根据具体的 HarmonyOS 版本和 API 文档进行调整
   */
  public async parse(): Promise<EBook> {
    try {
      if (!isReaderKitEnabled()) {
        logger.warn(TAG, `Reader Kit disabled, fallback parser will be used: ${this.filePath}`);
        return this.parseFallback();
      }
      logger.info(TAG, `开始使用 Reader Kit 解析电子书: ${this.filePath}, 格式: ${this.format}`);

      // 读取文件数据
      const fileBuffer = await this.readFileBuffer(this.filePath);
      
      // 使用 Reader Kit 解析（框架代码，需要根据实际 API 调整）
      const bookInfo = await this.parseWithReaderKit(fileBuffer);
      
      // 构建 EBook 对象
      const ebook = this.buildEBookFromReaderKit(bookInfo);
      ebook.fileSize = fileBuffer.byteLength;
      
      logger.info(TAG, `Reader Kit 解析完成: ${ebook.metadata.title}`);
      return ebook;
      
    } catch (error) {
      logger.error(TAG, `Reader Kit 解析失败: ${String(error instanceof Error ? error.message : error)}`);
      
      // 失败时使用降级方案（从文件名提取基本信息）
      return this.parseFallback();
    }
  }

  /**
   * 读取文件二进制数据
   */
  private async readFileBuffer(filePath: string): Promise<ArrayBuffer> {
    try {
      let openTarget: string = filePath;
      if (!filePath.startsWith('file://') && !filePath.startsWith('/')) {
        openTarget = `/${filePath}`;
      }

      let file = SafeFileUtils.openSync(openTarget, fileIo.OpenMode.READ_ONLY);
      let stat = SafeFileUtils.statSync(file.fd);
      let buffer = new ArrayBuffer(stat.size);
      let readLen = SafeFileUtils.readSync(file.fd, buffer);
      SafeFileUtils.closeSync(file);

      if (readLen !== stat.size) {
        throw new Error(`读取长度不一致: 期望 ${stat.size} 实际 ${readLen}`);
      }

      logger.debug(TAG, `文件读取成功，大小: ${stat.size} 字节`);
      return buffer;
    } catch (firstError) {
      const firstMsg = firstError instanceof Error ? firstError.message : String(firstError);

      try {
        if (filePath.startsWith('file://')) {
          const stripped = filePath.substring(7);
          const candidate = stripped.startsWith('/') ? stripped : `/${stripped}`;
          const file = SafeFileUtils.openSync(candidate, fileIo.OpenMode.READ_ONLY);
          const stat = SafeFileUtils.statSync(file.fd);
          const buffer = new ArrayBuffer(stat.size);
          const readLen = SafeFileUtils.readSync(file.fd, buffer);
          SafeFileUtils.closeSync(file);

          if (readLen !== stat.size) {
            throw new Error(`读取长度不一致: 期望 ${stat.size} 实际 ${readLen}`);
          }
          logger.debug(TAG, `文件读取成功（备用路径），大小: ${stat.size} 字节`);
          return buffer;
        }
        throw new Error(firstMsg);
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        logger.error(TAG, `文件读取失败: ${errorMsg}`);
        throw new Error(`文件读取失败: ${errorMsg}`);
      }
    }
  }

  /**
   * 使用 Reader Kit 解析电子书
   */
  private async parseWithReaderKit(fileBuffer: ArrayBuffer): Promise<ReaderKitBookInfo> {
    try {
      if (!isReaderKitEnabled()) {
        throw new Error('Reader Kit is unavailable in current environment');
      }
      const fileName = this.getFileNameFromPath(this.filePath);
      let candidatePath: string = this.filePath;
      
      // 处理 file:// 路径
      if (this.filePath.startsWith('file://')) {
        // 尝试使用原始路径，因为我们在 DataManagementPage 中已经确保了文件在沙箱中
        // 并且 ReaderKitTestPage 验证了直接传递 URI 给 getDefaultHandler 可能有问题，
        // 但这里我们假设传入的是沙箱路径。
        // 如果是 content uri，可能需要特殊处理，但目前我们假设是文件路径
        // 对于 file://docs，我们已经复制到了沙箱，所以这里应该是沙箱路径
      }

      // 获取 Handler
      const parserHandler: bookParser.BookParserHandler = await createReaderKitBookParserHandler(candidatePath);
      if (!parserHandler) {
        throw new Error('无法获取 BookParserHandler');
      }

      // 获取书籍信息
      // 使用 Record<string, Object> 保持动态字段读取的类型边界
      const rawInfo = parserHandler.getBookInfo();
      const infoObj = rawInfo as Object as Record<string, Object>;
      
      // 获取目录
      const rawCatalog = parserHandler.getCatalogList();
      const catalogObj = rawCatalog as Object as Array<Record<string, Object>>;

      // 构建章节列表
      const chapters: ReaderKitChapter[] = this.buildChaptersFromCatalog(catalogObj);

      const bookInfo: ReaderKitBookInfo = {
        title: (infoObj['title'] as string) || this.extractTitleFromFileName(fileName),
        author: (infoObj['author'] as string) || '未知作者',
        publisher: (infoObj['publisher'] as string) || '',
        publishDate: (infoObj['publishDate'] as string) || '',
        isbn: (infoObj['isbn'] as string) || '',
        language: (infoObj['language'] as string) || 'zh-CN',
        description: (infoObj['description'] as string) || `${this.format} 电子书`,
        coverImagePath: (infoObj['coverUrl'] as string) || '',
        chapters: chapters
      };
      return bookInfo;
    } catch (error) {
      logger.error(TAG, `Reader Kit 内部解析错误: ${error}`);
      if (error instanceof Error) {
        throw error;
      } else {
        throw new Error(String(error));
      }
    }
  }

  private buildChaptersFromCatalog(catalog: Array<Record<string, Object>>): ReaderKitChapter[] {
    const chapters: ReaderKitChapter[] = [];
    if (!catalog || catalog.length === 0) {
      return chapters;
    }

    for (let i: number = 0; i < catalog.length; i++) {
      const item = catalog[i];
      const ch: ReaderKitChapter = {
        id: (item['id'] as string) || `chapter_${i}`,
        title: (item['title'] as string) || `章节${i + 1}`,
        content: '' 
      };
      chapters.push(ch);
    }
    return chapters;
  }

  /**
   * 从 Reader Kit 返回的信息构建 EBook 对象
   */
  private buildEBookFromReaderKit(bookInfo: ReaderKitBookInfo): EBook {
    const now = Date.now();
    const bookId = `ebook_${this.format.toLowerCase()}_${now}_${Math.random().toString(36).substring(2, 9)}`;

    const metadata: EBookMetadata = {
      title: bookInfo.title,
      author: bookInfo.author,
      publisher: bookInfo.publisher,
      publishDate: bookInfo.publishDate,
      isbn: bookInfo.isbn,
      language: bookInfo.language,
      description: bookInfo.description,
      coverImagePath: bookInfo.coverImagePath,
      tags: [this.format],
      rating: 0
    };

    const ebook = new EBook(
      bookId,
      this.format,
      this.filePath,
      0,
      metadata,
      [],
      EBookStatus.UNREAD,
      null,
      null,
      now,
      now,
      false,
      0
    );

    // 添加章节
    if (bookInfo.chapters && bookInfo.chapters.length > 0) {
      ebook.chapters = bookInfo.chapters.map((ch, index) => {
        const chapter: EBookChapter = {
          id: ch.id || `chapter_${index}`,
          bookId: bookId,
          title: ch.title,
          content: ch.content,
          chapterNumber: index + 1,
          wordCount: ch.content.length,
          startPosition: 0,
          endPosition: ch.content.length,
          createTime: now
        };
        return chapter;
      });
    } else {
      const defaultChapter: EBookChapter = {
        id: `chapter_default_${now}`,
        bookId: bookId,
        title: '第1章',
        content: '内容加载中...',
        chapterNumber: 1,
        wordCount: 0,
        startPosition: 0,
        endPosition: 0,
        createTime: now
      };
      ebook.chapters.push(defaultChapter);
    }

    return ebook;
  }

  /**
   * 降级解析方案（当 Reader Kit 不可用时）
   */
  private async parseFallback(): Promise<EBook> {
    logger.warn(TAG, `使用降级方案解析: ${this.format}`);
    
    const fileName = this.getFileNameFromPath(this.filePath);
    const title = this.extractTitleFromFileName(fileName);
    const now = Date.now();
    const bookId = `ebook_${this.format.toLowerCase()}_${now}_${Math.random().toString(36).substring(2, 9)}`;

    const metadata: EBookMetadata = {
      title: title,
      author: '未知作者',
      publisher: '',
      publishDate: '',
      isbn: '',
      language: 'zh-CN',
      description: `${this.format} 格式电子书`,
      coverImagePath: '',
      tags: [this.format],
      rating: 0
    };

    const ebook = new EBook(
      bookId,
      this.format,
      this.filePath,
      0,
      metadata,
      [],
      EBookStatus.UNREAD,
      null,
      null,
      now,
      now,
      false,
      0
    );

    // 添加占位符章节
    const placeholderChapter: EBookChapter = {
      id: `chapter_${now}`,
      bookId: bookId,
      title: '第1章',
      content: '请在阅读器中打开查看内容',
      chapterNumber: 1,
      wordCount: 0,
      startPosition: 0,
      endPosition: 0,
      createTime: now
    };
    ebook.chapters.push(placeholderChapter);

    return ebook;
  }

  /**
   * 从文件路径获取文件名
   */
  private getFileNameFromPath(filePath: string): string {
    const parts = filePath.split('/');
    const encodedFileName = parts[parts.length - 1] || 'unknown_file';
    
    try {
      return decodeURIComponent(encodedFileName);
    } catch (error) {
      return encodedFileName;
    }
  }

  /**
   * 从文件名提取书名
   */
  private extractTitleFromFileName(fileName: string): string {
    const nameWithoutExt = fileName.replace(/\.(txt|epub|mobi|azw|azw3)$/i, '');
    const cleanName = nameWithoutExt.replace(/[\[\]()（）【】_-]+$/, '').trim();
    return cleanName || '未知书名';
  }

  /**
   * 获取 Reader Kit 文件类型
   */
  private getReaderKitFileType(): string {
    // ReaderKit 当前按文件路径创建处理器，这里保留格式字符串用于诊断和兜底路由。
    return this.format;
  }
}

/**
 * Reader Kit 返回的书籍信息接口
 */
interface ReaderKitBookInfo {
  title: string;
  author: string;
  publisher: string;
  publishDate: string;
  isbn: string;
  language: string;
  description: string;
  coverImagePath: string;
  chapters: ReaderKitChapter[];
}

/**
 * Reader Kit 章节信息接口
 */
interface ReaderKitChapter {
  id: string;
  title: string;
  content: string;
}

interface ReaderKitCatalogItem {
  id: string;
  title: string;
}

