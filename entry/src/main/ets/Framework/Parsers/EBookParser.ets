// 文件路径: entry/src/main/ets/Framework/Parsers/EBookParser.ets
/**
 * 电子书解析器基类
 * 提供统一的电子书解析接口
 */

import { EBook, EBookFormat, EBookMetadata, EBookChapter, EBookStatus, EBookPageMode } from '../../Models/EBookModels';
import { logger } from '../../Utils/Logger';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { pdfService } from '@kit.PDFKit';
import { TxtMetadataExtractor } from './TxtMetadataExtractor';
import { isReaderKitEnabled } from '../Initialization/ReaderKitFeatureGate';

const TAG = 'EBookParser';

interface ReaderKitBookParserHandler {
  getBookInfo(): Promise<Object>;
  getCatalogList(): Promise<Object>;
  getResourceContent(spineIndex: number, resourcePath: string): ArrayBuffer;
}

interface ReaderKitBookParserApi {
  getDefaultHandler(path: string): Promise<ReaderKitBookParserHandler | null>;
}

interface ReaderKitDynamicModule {
  bookParser?: ReaderKitBookParserApi;
}

let cachedBookParser: ReaderKitBookParserApi | null = null;
let readerKitLoadAttempted: boolean = false;

async function getReaderKitBookParser(): Promise<ReaderKitBookParserApi | null> {
  if (!isReaderKitEnabled()) {
    return null;
  }

  if (cachedBookParser) {
    return cachedBookParser;
  }

  if (readerKitLoadAttempted) {
    return null;
  }

  readerKitLoadAttempted = true;
  try {
    const readerKitModule = await import('@kit.ReaderKit');
    const parser = (readerKitModule as Object as ReaderKitDynamicModule).bookParser;
    if (!parser) {
      logger.error(TAG, 'Reader Kit module loaded but bookParser is missing');
      return null;
    }
    cachedBookParser = parser;
    logger.info(TAG, 'Reader Kit bookParser loaded lazily');
    return cachedBookParser;
  } catch (error) {
    logger.error(TAG, `Failed to lazy-load Reader Kit: ${String(error instanceof Error ? error.message : error)}`);
    return null;
  }
}

// 章节标题正则表达式（支持多种格式）
const CHAPTER_PATTERNS = [
  /^第\s*([0-9零一二三四五六七八九十百千万亿]+)\s*[章回卷节集部篇]\s*(.*)$/,
  /^([0-9零一二三四五六七八九十百千万亿]+)\s*[、.．·]\s*(.+)$/,
  /^Chapter\s+(\d+)[：:\s]+(.*)$/i,
  /^卷\s*([0-9零一二三四五六七八九十百千万亿]+)\s*(.*)$/,
  /^\s*(\d+)\s*[、.．·]\s*(.+)$/,
  /^[【\[]第\s*([0-9零一二三四五六七八九十百千万亿]+)\s*[章回卷节集部篇][】\]]\s*(.*)$/,
];

/**
 * 电子书解析器抽象基类
 */
export abstract class EBookParser {
  protected filePath: string;
  protected format: EBookFormat;

  constructor(filePath: string, format: EBookFormat) {
    this.filePath = filePath;
    this.format = format;
  }

  /**
   * 解析电子书
   * @returns 解析后的电子书对象
   */
  public abstract parse(): Promise<EBook>;

  /**
   * 生成默认的电子书对象
   */
  protected generateDefaultEBook(filePath: string, format: EBookFormat, metadata: EBookMetadata): EBook {
    const now = Date.now();
    const bookId = `ebook_${format.toLowerCase()}_${now}_${Math.random().toString(36).substring(2, 9)}`;

    return new EBook(
      bookId,
      format,
      filePath,
      0, // fileSize will be updated after reading
      metadata,
      [], // chapters will be added during parsing
      EBookStatus.UNREAD,
      null, // reading progress will be initialized by constructor
      null, // reading settings will be initialized by constructor
      now,
      now,
      false,
      0 // totalWordCount will be calculated
    );
  }

  /**
   * 从文件名提取书名
   */
  protected extractTitleFromFileName(fileName: string): string {
    // 移除文件扩展名
    const nameWithoutExt = fileName.replace(/\.(txt|epub|mobi|azw|azw3|pdf)$/i, '');
    // 移除可能的特殊字符和数字后缀
    const cleanName = nameWithoutExt.replace(/[\[\]()（）【】_-]+$/, '').trim();
    return cleanName || '未知书名';
  }

  /**
   * 从文件路径获取文件名
   */
  protected getFileNameFromPath(filePath: string): string {
    const parts = filePath.split('/');
    const encodedFileName = parts[parts.length - 1] || 'unknown_file';
    
    // 解码URL编码的文件名（如 %E7%AC%AC -> 第）
    try {
      return decodeURIComponent(encodedFileName);
    } catch (error) {
      logger.warn(TAG, `URL解码失败，使用原始文件名: ${encodedFileName}`);
      return encodedFileName;
    }
  }
}

/**
 * Reader Kit 电子书解析器
 */
class ReaderKitEBookParser extends EBookParser {
  constructor(filePath: string, format: EBookFormat) {
    super(filePath, format);
  }

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

  public async parse(): Promise<EBook> {
    try {
      if (!isReaderKitEnabled()) {
        logger.warn(TAG, `Reader Kit temporarily disabled, fallback parser will be used: ${this.filePath}`);
        return this.parseFallback();
      }
      logger.info(TAG, `开始使用 Reader Kit 解析电子书: ${this.filePath}, 格式: ${this.format}`);
      const fileBuffer = await this.readFileBuffer(this.filePath);
      const bookInfo = await this.parseWithReaderKit(fileBuffer);
      const ebook = this.buildEBookFromReaderKit(bookInfo);
      ebook.fileSize = fileBuffer.byteLength;
      logger.info(TAG, `Reader Kit 解析完成: ${ebook.metadata.title}`);
      return ebook;
    } catch (error) {
      logger.error(TAG, `Reader Kit 解析失败: ${String(error instanceof Error ? error.message : error)}`);
      return this.parseFallback();
    }
  }

  private async readFileBuffer(filePath: string): Promise<ArrayBuffer> {
    try {
      let openTarget: string = filePath;
      if (!filePath.startsWith('file://') && !filePath.startsWith('/')) {
        openTarget = `/${filePath}`;
      }
      let file = fileIo.openSync(openTarget, fileIo.OpenMode.READ_ONLY);
      let stat = fileIo.statSync(file.fd);
      let buffer = new ArrayBuffer(stat.size);
      let readLen = fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);
      if (readLen !== stat.size) {
        throw new Error(`读取长度不一致: 期望 ${stat.size} 实际 ${readLen}`);
      }
      return buffer;
    } catch (firstError) {
      const firstMsg = firstError instanceof Error ? firstError.message : String(firstError);
      try {
        if (filePath.startsWith('file://')) {
          const stripped = filePath.substring(7);
          const candidate = stripped.startsWith('/') ? stripped : `/${stripped}`;
          const file = fileIo.openSync(candidate, fileIo.OpenMode.READ_ONLY);
          const stat = fileIo.statSync(file.fd);
          const buffer = new ArrayBuffer(stat.size);
          const readLen = fileIo.readSync(file.fd, buffer);
          fileIo.closeSync(file);
          if (readLen !== stat.size) {
            throw new Error(`读取长度不一致: 期望 ${stat.size} 实际 ${readLen}`);
          }
          return buffer;
        }
        throw new Error(firstMsg);
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        throw new Error(`文件读取失败: ${errorMsg}`);
      }
    }
  }

  private async parseWithReaderKit(fileBuffer: ArrayBuffer): Promise<ReaderKitBookInfo> {
    try {
      const fileName = this.getFileNameFromPath(this.filePath);
      let candidatePath: string = this.filePath;
      logger.info(TAG, `[ReaderKit] 开始解析，路径: ${candidatePath}`);
      
      const bookParser = await getReaderKitBookParser();
      if (!bookParser) {
        throw new Error('Reader Kit is unavailable in current environment');
      }
      const parserHandler = await bookParser.getDefaultHandler(candidatePath);
      if (!parserHandler) {
        throw new Error('无法获取 BookParserHandler');
      }
      logger.info(TAG, `[ReaderKit] Handler 获取成功`);

      // 获取书籍信息 - 使用 Object 类型转换以访问动态属性
      const rawInfo = await parserHandler.getBookInfo();
      // 打印完整的 BookInfo 对象以查看实际属性名
      logger.info(TAG, `[ReaderKit] BookInfo 原始数据: ${JSON.stringify(rawInfo)}`);
      const infoObj = rawInfo as Object as Record<string, Object>;
      
      // 打印所有可用的属性键，帮助调试
      const allKeys = Object.keys(infoObj);
      logger.info(TAG, `[ReaderKit] BookInfo 所有属性键: ${allKeys.join(', ')}`);
      
      // 获取目录
      const rawCatalog = await parserHandler.getCatalogList();
      const catalogArray = rawCatalog as Object as Array<Record<string, Object>>;
      logger.info(TAG, `[ReaderKit] 目录数量: ${catalogArray?.length || 0}`);
      if (catalogArray && catalogArray.length > 0) {
        logger.info(TAG, `[ReaderKit] 第一个目录项: ${JSON.stringify(catalogArray[0])}`);
      }

      // 构建章节列表
      const chapters: ReaderKitChapter[] = this.buildChaptersFromCatalog(catalogArray);
      
      // 详细打印每个元数据字段的值，帮助调试
      logger.info(TAG, `[ReaderKit] 元数据详情:`);
      logger.info(TAG, `  - bookTitle: "${infoObj['bookTitle'] || ''}"`);
      logger.info(TAG, `  - bookCreator: "${infoObj['bookCreator'] || ''}"`);
      logger.info(TAG, `  - bookPublisher: "${infoObj['bookPublisher'] || ''}"`);
      logger.info(TAG, `  - bookPublishDate: "${infoObj['bookPublishDate'] || ''}"`);
      logger.info(TAG, `  - bookDescription: "${infoObj['bookDescription'] || ''}"`);
      logger.info(TAG, `  - bookLanguage: "${infoObj['bookLanguage'] || ''}"`);
      logger.info(TAG, `  - bookCoverImage: "${infoObj['bookCoverImage'] || ''}"`);
      
      // 根据 Reader Kit 实际返回的属性名进行映射
      // BookInfo 实际属性: bookTitle, bookCreator, bookPublishDate, bookLanguage, bookCoverImage, bookCharset, bookType, isRtl
      let author = this.getStringProperty(infoObj, ['bookCreator', 'author', 'creator', 'bookAuthor']);
      let publisher = this.getStringProperty(infoObj, ['bookPublisher', 'publisher', 'press']);
      let description = this.getStringProperty(infoObj, ['bookDescription', 'description', 'desc', 'summary', 'intro']);
      
      // 如果作者为空，尝试从目录中的"版权信息"或"作者简介"章节名推断
      if (!author && catalogArray && catalogArray.length > 0) {
        for (const item of catalogArray) {
          const catalogName = String(item['catalogName'] || '');
          // 检查是否有作者相关的章节
          if (catalogName.includes('作者') || catalogName.includes('著者')) {
            logger.info(TAG, `[ReaderKit] 发现作者相关章节: ${catalogName}`);
            // 可以尝试从章节名中提取作者信息
          }
        }
      }
      
      const bookInfo: ReaderKitBookInfo = {
        title: this.getStringProperty(infoObj, ['bookTitle', 'title', 'name', 'bookName']) || this.extractTitleFromFileName(fileName),
        author: author || '未知作者',
        publisher: publisher,
        publishDate: this.getStringProperty(infoObj, ['bookPublishDate', 'publishDate', 'pubDate', 'date']) || '',
        isbn: this.getStringProperty(infoObj, ['bookIsbn', 'isbn', 'ISBN']) || '',
        language: this.getStringProperty(infoObj, ['bookLanguage', 'language', 'lang']) || 'zh-CN',
        description: description || `${this.format} 电子书`,
        coverImagePath: this.getStringProperty(infoObj, ['bookCoverImage', 'coverUrl', 'cover', 'coverPath', 'coverImage']) || '',
        chapters: chapters
      };
      
      logger.info(TAG, `[ReaderKit] 解析完成: 书名=${bookInfo.title}, 作者=${bookInfo.author}, 出版社=${bookInfo.publisher}, 简介长度=${bookInfo.description.length}, 章节数=${chapters.length}`);
      return bookInfo;
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `[ReaderKit] 解析失败: ${errorMsg}`);
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }
  
  /**
   * 从对象中获取字符串属性，尝试多个可能的属性名
   * 跳过空字符串，只返回有实际内容的值
   */
  private getStringProperty(obj: Record<string, Object>, keys: string[]): string {
    for (const key of keys) {
      const value = obj[key];
      if (value !== undefined && value !== null) {
        const strValue = String(value).trim();
        // 跳过空字符串，继续尝试下一个键
        if (strValue.length > 0) {
          return strValue;
        }
      }
    }
    return '';
  }

  private buildChaptersFromCatalog(catalog: Array<Record<string, Object>>): ReaderKitChapter[] {
    const chapters: ReaderKitChapter[] = [];
    if (!catalog || catalog.length === 0) {
      return chapters;
    }
    for (let i: number = 0; i < catalog.length; i++) {
      const item = catalog[i];
      // 根据 Reader Kit 实际返回的属性名进行映射
      // CatalogItem 实际属性: catalogId, catalogName, catalogLevel, href, resourceFile
      const chapterId = this.getStringProperty(item, ['catalogId', 'id', 'chapterId', 'index']) || `chapter_${i}`;
      const chapterTitle = this.getStringProperty(item, ['catalogName', 'title', 'name', 'chapterTitle', 'label']) || `章节${i + 1}`;
      const ch: ReaderKitChapter = {
        id: chapterId,
        title: chapterTitle,
        content: ''
      };
      chapters.push(ch);
    }
    return chapters;
  }

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
      bookId, this.format, this.filePath, 0, metadata, [],
      EBookStatus.UNREAD, null, null, now, now, false, 0
    );
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
      ebook.chapters.push({
        id: `chapter_default_${now}`,
        bookId: bookId,
        title: '第1章',
        content: '内容加载中...',
        chapterNumber: 1,
        wordCount: 0,
        startPosition: 0,
        endPosition: 0,
        createTime: now
      });
    }
    return ebook;
  }

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
      bookId, this.format, this.filePath, 0, metadata, [],
      EBookStatus.UNREAD, null, null, now, now, false, 0
    );
    ebook.chapters.push({
      id: `chapter_${now}`,
      bookId: bookId,
      title: '第1章',
      content: '请在阅读器中打开查看内容',
      chapterNumber: 1,
      wordCount: 0,
      startPosition: 0,
      endPosition: 0,
      createTime: now
    });
    return ebook;
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

/**
 * 电子书封面提取结果
 */
export interface EBookCoverExtractionResult {
  success: boolean;
  coverPath: string;
  candidateImages: string[];
  errorMessage?: string;
}

/**
 * 电子书封面提取器
 * 使用 Reader Kit 提取电子书封面图片
 * 对于 PDF 格式，使用 PDF Kit 的 convertToImage 方法
 */
export class EBookCoverExtractor {
  private static TAG: string = 'EBookCoverExtractor';
  private static readonly MAX_CANDIDATE_IMAGES = 5;

  /**
   * 提取电子书封面
   * @param filePath 电子书文件路径
   * @param savePath 封面保存路径
   * @returns 提取结果
   */
  public static async extractCover(filePath: string, savePath: string): Promise<EBookCoverExtractionResult> {
    try {
      logger.info(EBookCoverExtractor.TAG, `开始提取电子书封面: ${filePath}`);

      // 检查是否为 PDF 格式
      if (filePath.toLowerCase().endsWith('.pdf')) {
        return await EBookCoverExtractor.extractPdfCover(filePath, savePath);
      }

      if (!isReaderKitEnabled()) {
        logger.warn(EBookCoverExtractor.TAG, `Reader Kit temporarily disabled, skip cover extraction: ${filePath}`);
        return {
          success: false,
          coverPath: '',
          candidateImages: [],
          errorMessage: 'Reader Kit is temporarily disabled'
        };
      }

      // 获取 Reader Kit Handler（用于非 PDF 格式）
      const bookParser = await getReaderKitBookParser();
      if (!bookParser) {
        throw new Error('Reader Kit is unavailable in current environment');
      }
      const parserHandler = await bookParser.getDefaultHandler(filePath);
      if (!parserHandler) {
        throw new Error('无法获取 BookParserHandler');
      }

      // 获取书籍信息
      const rawInfo = await parserHandler.getBookInfo();
      const infoObj = rawInfo as Object as Record<string, Object>;
      const coverImageRef = String(infoObj['bookCoverImage'] || '');

      logger.info(EBookCoverExtractor.TAG, `封面图片引用: ${coverImageRef}`);

      if (!coverImageRef || coverImageRef.length === 0) {
        logger.warn(EBookCoverExtractor.TAG, '电子书没有封面图片引用');
        return {
          success: false,
          coverPath: '',
          candidateImages: [],
          errorMessage: '电子书没有封面图片'
        };
      }

      // 使用官方 API: getResourceContent(spineIndex, resourcePath)
      // 根据官方示例代码，获取封面时 spineIndex 传 -1
      try {
        logger.info(EBookCoverExtractor.TAG, `尝试使用 getResourceContent(-1, "${coverImageRef}") 提取封面...`);
        
        // 直接调用 parserHandler 的 getResourceContent 方法
        // 注意：这是同步方法，不需要 await
        const resourceData = parserHandler.getResourceContent(-1, coverImageRef);
        
        if (resourceData && resourceData.byteLength > 0) {
          logger.info(EBookCoverExtractor.TAG, `成功获取封面数据，大小: ${resourceData.byteLength} 字节`);
          // 保存封面图片
          const savedPath = await EBookCoverExtractor.saveImageToFile(resourceData, savePath, coverImageRef);
          if (savedPath) {
            logger.info(EBookCoverExtractor.TAG, `封面图片保存成功: ${savedPath}`);
            return {
              success: true,
              coverPath: savedPath,
              candidateImages: [savedPath]
            };
          }
        } else {
          logger.warn(EBookCoverExtractor.TAG, `getResourceContent 返回空数据`);
        }
      } catch (extractError) {
        logger.warn(EBookCoverExtractor.TAG, `使用 getResourceContent 提取封面失败: ${String(extractError)}`);
      }
      
      logger.warn(EBookCoverExtractor.TAG, `无法提取封面图片`);

      // 如果直接提取失败，返回封面引用信息（供后续处理）
      return {
        success: false,
        coverPath: '',
        candidateImages: [],
        errorMessage: `封面引用: ${coverImageRef}，但无法提取`
      };

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(EBookCoverExtractor.TAG, `提取封面失败: ${errorMsg}`);
      return {
        success: false,
        coverPath: '',
        candidateImages: [],
        errorMessage: errorMsg
      };
    }
  }

  /**
   * 保存图片到文件
   */
  private static async saveImageToFile(imageData: ArrayBuffer, basePath: string, originalName: string): Promise<string | null> {
    try {
      // 确定文件扩展名
      const ext = EBookCoverExtractor.getImageExtension(originalName, imageData);
      const fileName = `cover_${Date.now()}${ext}`;
      const fullPath = `${basePath}/${fileName}`;

      // 确保目录存在
      try {
        fileIo.mkdirSync(basePath, true);
      } catch (e) {
        // 目录可能已存在
      }

      // 写入文件
      const file = fileIo.openSync(fullPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, imageData);
      fileIo.closeSync(file);

      logger.info(EBookCoverExtractor.TAG, `图片保存成功: ${fullPath}, 大小: ${imageData.byteLength} 字节`);
      return fullPath;
    } catch (error) {
      logger.error(EBookCoverExtractor.TAG, `保存图片失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 获取图片扩展名
   */
  private static getImageExtension(originalName: string, imageData: ArrayBuffer): string {
    // 从原始文件名获取扩展名
    const match = originalName.match(/\.(jpg|jpeg|png|gif|webp|bmp)$/i);
    if (match) {
      return `.${match[1].toLowerCase()}`;
    }

    // 通过文件头检测图片格式
    const bytes = new Uint8Array(imageData.slice(0, 8));
    if (bytes[0] === 0xFF && bytes[1] === 0xD8) {
      return '.jpg';
    } else if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) {
      return '.png';
    } else if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) {
      return '.gif';
    } else if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46) {
      return '.webp';
    }

    return '.jpg'; // 默认使用 jpg
  }

  /**
   * 提取 PDF 封面
   * 使用 PDF Kit 的 getPagePixelMap 方法获取第一页的 PixelMap，
   * 然后使用 ImagePacker 异步打包为图片文件。
   * 这种方式比 convertToImage 更不容易阻塞主线程。
   */
  private static async extractPdfCover(filePath: string, savePath: string): Promise<EBookCoverExtractionResult> {
    logger.info(EBookCoverExtractor.TAG, `开始提取 PDF 封面: ${filePath}`);
    
    try {
      // 创建输出目录
      const outputDir = savePath.substring(0, savePath.lastIndexOf('/'));
      
      // 确保目录存在
      try {
        fileIo.mkdirSync(outputDir, true);
      } catch (mkdirError) {
        // 目录可能已存在
      }
      
      logger.info(EBookCoverExtractor.TAG, `开始获取 PDF 第一页 PixelMap`);
      
      // 创建 PDF 文档对象
      const pdfDocument = new pdfService.PdfDocument();
      const loadResult = pdfDocument.loadDocument(filePath);
      
      if (loadResult !== pdfService.ParseResult.PARSE_SUCCESS) {
        logger.warn(EBookCoverExtractor.TAG, `PDF 加载失败: ${loadResult}`);
        return {
          success: false,
          coverPath: '',
          candidateImages: [],
          errorMessage: `PDF 加载失败: ${loadResult}`
        };
      }
      
      const pageCount = pdfDocument.getPageCount();
      if (pageCount <= 0) {
        logger.warn(EBookCoverExtractor.TAG, `PDF 页数为 0`);
        return {
          success: false,
          coverPath: '',
          candidateImages: [],
          errorMessage: 'PDF 页数为 0'
        };
      }
      
      // 获取第一页
      const pdfPage: pdfService.PdfPage = pdfDocument.getPage(0);
      if (!pdfPage) {
        logger.warn(EBookCoverExtractor.TAG, `无法获取 PDF 第一页`);
        return {
          success: false,
          coverPath: '',
          candidateImages: [],
          errorMessage: '无法获取 PDF 第一页'
        };
      }
      
      // 使用 getPagePixelMap 获取页面的 PixelMap
      const pixelMap: image.PixelMap | null = pdfPage.getPagePixelMap();
      if (!pixelMap) {
        logger.warn(EBookCoverExtractor.TAG, `获取 PDF 页面 PixelMap 失败`);
        return {
          success: false,
          coverPath: '',
          candidateImages: [],
          errorMessage: '获取 PDF 页面 PixelMap 失败'
        };
      }
      
      // 使用 ImagePacker 异步将 PixelMap 打包为 WebP 格式
      // WebP 格式比 JPEG 更节省空间，质量70在文件大小和画质之间取得良好平衡
      const packOpts: image.PackingOption = {
        format: 'image/webp',
        quality: 70
      };
      const imagePackerApi = image.createImagePacker();
      
      try {
        const imgBuffer = await imagePackerApi.packToData(pixelMap, packOpts);
        
        // 释放 PixelMap 资源
        pixelMap.release();
        
        // 如果目标文件已存在，先删除
        try {
          fileIo.unlinkSync(savePath);
        } catch (unlinkError) {
          // 文件不存在，忽略
        }
        
        // 异步写入文件
        const file = fileIo.openSync(savePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
        await fileIo.write(file.fd, imgBuffer);
        fileIo.closeSync(file.fd);
        
        logger.info(EBookCoverExtractor.TAG, `PDF 封面图片生成成功: ${savePath}`);
        
        return {
          success: true,
          coverPath: savePath,
          candidateImages: [savePath],
          errorMessage: ''
        };
        
      } finally {
        imagePackerApi.release();
      }
      
    } catch (error) {
      logger.error(EBookCoverExtractor.TAG, `PDF 封面提取失败: ${String(error)}`);
      return {
        success: false,
        coverPath: '',
        candidateImages: [],
        errorMessage: `PDF 封面提取失败: ${String(error)}`
      };
    }
  }
}

/**
 * 电子书解析器工厂
 */
export class EBookParserFactory {
  /**
   * 根据文件路径创建对应的解析器
   * 
   * 解析策略：
   * - EPUB/MOBI/AZW/AZW3: 优先使用 Reader Kit（官方 API）
   * - PDF: 使用 Web 组件预览方案
   * - TXT: 使用文件读取 + 自定义解析
   */
  public static createParser(filePath: string): EBookParser | null {
    const format = EBookParserFactory.detectFormat(filePath);
    
    if (!format) {
      logger.warn(TAG, `无法识别的电子书格式: ${filePath}`);
      return null;
    }

    // 优先使用 Reader Kit 解析支持的格式（除了 TXT，TXT 我们有自定义实现）
    if (isReaderKitEnabled() && ReaderKitEBookParser.isSupportedFormat(format) && format !== EBookFormat.TXT) {
      logger.info(TAG, `使用 Reader Kit 解析: ${format}`);
      return new ReaderKitEBookParser(filePath, format);
    }
    
    // 其他格式使用自定义解析器
    switch (format) {
      case EBookFormat.TXT:
        return new TxtParser(filePath);
      case EBookFormat.PDF:
        return new PdfParser(filePath);
      default:
        logger.warn(TAG, `暂不支持的电子书格式: ${filePath} (Reader Kit 已禁用)`);
        return null;
    }
  }

  /**
   * 检测文件格式
   */
  private static detectFormat(filePath: string): EBookFormat | null {
    const extension = filePath.toLowerCase().split('.').pop();
    
    switch (extension) {
      case 'txt':
        return EBookFormat.TXT;
      case 'epub':
        return EBookFormat.EPUB;
      case 'mobi':
        return EBookFormat.MOBI;
      case 'azw':
        return EBookFormat.AZW;
      case 'azw3':
        return EBookFormat.AZW3;
      case 'pdf':
        return EBookFormat.PDF;
      default:
        return null;
    }
  }
}

/**
 * TXT解析器实现
 */
class TxtParser extends EBookParser {
  private encoding: string = 'utf-8';

  constructor(filePath: string) {
    super(filePath, EBookFormat.TXT);
  }

  public async parse(): Promise<EBook> {
    logger.info(TAG, `开始解析TXT文件: ${this.filePath}`);

    try {
      // 1. 读取文件内容（自动检测编码）
      const content = await this.readFileContent();
      logger.debug(TAG, `文件内容长度: ${content.length} 字符, 编码: ${this.encoding}`);

      // 2. 获取文件大小
      const fileSize = await this.getFileSize();
      
      // 3. 获取文件名
      const fileName = this.getFileNameFromPath(this.filePath);

      // 4. 使用智能提取器提取元数据和章节信息
      const extractionResult = TxtMetadataExtractor.extract(content, fileName);
      
      // 5. 处理标签
      if (extractionResult.metadata.tags.length === 0) {
        extractionResult.metadata.tags = this.extractTagsFromFileName(fileName);
      } else {
        // 合并标签并去重
        const fileNameTags = this.extractTagsFromFileName(fileName);
        const seen = new Set<string>();
        const mergedTags: string[] = [];
        for (const tag of extractionResult.metadata.tags) {
          if (!seen.has(tag)) {
            seen.add(tag);
            mergedTags.push(tag);
          }
        }
        for (const tag of fileNameTags) {
          if (!seen.has(tag)) {
            seen.add(tag);
            mergedTags.push(tag);
          }
        }
        extractionResult.metadata.tags = mergedTags;
      }
      if (!extractionResult.metadata.tags.includes('TXT')) {
        extractionResult.metadata.tags.unshift('TXT');
      }
      
      logger.debug(TAG, `提取的元数据: ${JSON.stringify(extractionResult.metadata)}`);

      // 7. 创建电子书对象
      const ebook = this.generateDefaultEBook(this.filePath, EBookFormat.TXT, extractionResult.metadata);
      ebook.fileSize = fileSize;

      // 8. 使用智能提取器的章节信息构建章节列表
      if (extractionResult.chapters.length > 0) {
        ebook.chapters = this.buildChaptersFromExtraction(content, extractionResult.chapters, ebook.id);
      } else {
        // 降级到原有的章节分割逻辑
        ebook.chapters = this.splitIntoChapters(content, ebook.id);
      }

      // 9. 计算总字数
      ebook.totalWordCount = this.calculateTotalWordCount(ebook.chapters);

      logger.info(TAG, `TXT文件解析完成: ${extractionResult.metadata.title}, 章节数: ${ebook.chapters.length}, 总字数: ${ebook.totalWordCount}`);

      return ebook;
    } catch (error) {
      logger.error(TAG, `解析TXT文件失败: ${String(error instanceof Error ? error.message : error)}`);
      throw error as Error;
    }
  }
  
  /**
   * 根据智能提取器的章节信息构建章节列表
   */
  private buildChaptersFromExtraction(content: string, chapterInfos: import('./TxtMetadataExtractor').TxtChapterInfo[], bookId: string): EBookChapter[] {
    const chapters: EBookChapter[] = [];
    const now = Date.now();
    
    for (let i = 0; i < chapterInfos.length; i++) {
      const info = chapterInfos[i];
      const chapterContent = content.substring(info.startPosition, info.endPosition).trim();
      
      // 移除章节标题行（避免重复）
      const lines = chapterContent.split('\n');
      const contentWithoutTitle = lines.length > 1 ? lines.slice(1).join('\n').trim() : chapterContent;
      
      const chapter: EBookChapter = {
        id: `${bookId}_chapter_${i}`,
        bookId: bookId,
        chapterNumber: info.chapterNumber || (i + 1),
        title: info.title,
        content: contentWithoutTitle,
        startPosition: info.startPosition,
        endPosition: info.endPosition,
        wordCount: this.countWords(contentWithoutTitle),
        createTime: now
      };
      chapters.push(chapter);
    }
    
    return chapters;
  }

  /**
   * 读取文件内容（支持多种编码自动检测）
   */
  private async readFileContent(): Promise<string> {
    // 先读取文件的原始字节
    const buffer = await this.readFileBuffer();
    
    // 检测编码并解码
    const encoding = this.detectEncodingFromBuffer(buffer);
    this.encoding = encoding;
    logger.info(TAG, `检测到文件编码: ${encoding}`);
    
    try {
      const decoder = new util.TextDecoder(encoding);
      const text = decoder.decodeToString(new Uint8Array(buffer));
      
      // 验证解码结果
      if (this.hasGarbledText(text)) {
        // 尝试其他编码
        const alternativeEncodings = ['gb18030', 'gbk', 'gb2312', 'utf-8'];
        for (const altEncoding of alternativeEncodings) {
          if (altEncoding === encoding) continue;
          try {
            const altDecoder = new util.TextDecoder(altEncoding);
            const altText = altDecoder.decodeToString(new Uint8Array(buffer));
            if (!this.hasGarbledText(altText)) {
              logger.info(TAG, `使用备选编码 ${altEncoding} 解码成功`);
              this.encoding = altEncoding;
              return altText;
            }
          } catch (e) {
            // 继续尝试下一个编码
          }
        }
      }
      
      return text;
    } catch (error) {
      logger.error(TAG, `解码失败: ${String(error)}`);
      // 降级到 UTF-8
      const decoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(new Uint8Array(buffer));
    }
  }
  
  /**
   * 读取文件原始字节
   */
  private async readFileBuffer(): Promise<ArrayBuffer> {
    try {
      let openTarget: string = this.filePath;
      if (!this.filePath.startsWith('file://') && !this.filePath.startsWith('/')) {
        openTarget = `/${this.filePath}`;
      }

      let file = fileIo.openSync(openTarget, fileIo.OpenMode.READ_ONLY);
      let stat = fileIo.statSync(file.fd);
      let buffer = new ArrayBuffer(stat.size);
      let readLen = fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);

      if (readLen !== stat.size) {
        throw new Error(`读取长度不一致: 期望 ${stat.size} 实际 ${readLen}`);
      }

      return buffer;
    } catch (firstError) {
      const firstMsg = firstError instanceof Error ? firstError.message : String(firstError);
      try {
        if (this.filePath.startsWith('file://')) {
          const stripped = this.filePath.substring(7);
          const candidate = stripped.startsWith('/') ? stripped : `/${stripped}`;
          const file = fileIo.openSync(candidate, fileIo.OpenMode.READ_ONLY);
          const stat = fileIo.statSync(file.fd);
          const buffer = new ArrayBuffer(stat.size);
          const readLen = fileIo.readSync(file.fd, buffer);
          fileIo.closeSync(file);

          if (readLen !== stat.size) {
            throw new Error(`读取长度不一致: 期望 ${stat.size} 实际 ${readLen}`);
          }
          return buffer;
        }
        throw new Error(firstMsg);
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        logger.error(TAG, `读取文件失败: ${errorMsg}`);
        throw new Error(`无法读取文件: ${this.filePath}`);
      }
    }
  }
  
  /**
   * 从文件头检测编码
   */
  private detectEncodingFromBuffer(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    const len = Math.min(bytes.length, 4096); // 检查前 4KB
    
    // 检查 BOM (Byte Order Mark)
    if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
      return 'utf-8';
    }
    if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
      return 'utf-16le';
    }
    if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
      return 'utf-16be';
    }
    
    // 统计字节特征来判断编码
    let utf8Score = 0;
    let gbkScore = 0;
    let i = 0;
    
    while (i < len) {
      const b = bytes[i];
      
      // ASCII 字符
      if (b < 0x80) {
        i++;
        continue;
      }
      
      // UTF-8 多字节序列检测
      if (b >= 0xC0 && b < 0xE0 && i + 1 < len) {
        // 2字节 UTF-8
        if ((bytes[i + 1] & 0xC0) === 0x80) {
          utf8Score += 2;
          i += 2;
          continue;
        }
      } else if (b >= 0xE0 && b < 0xF0 && i + 2 < len) {
        // 3字节 UTF-8 (常见中文)
        if ((bytes[i + 1] & 0xC0) === 0x80 && (bytes[i + 2] & 0xC0) === 0x80) {
          utf8Score += 3;
          i += 3;
          continue;
        }
      } else if (b >= 0xF0 && b < 0xF8 && i + 3 < len) {
        // 4字节 UTF-8
        if ((bytes[i + 1] & 0xC0) === 0x80 && (bytes[i + 2] & 0xC0) === 0x80 && (bytes[i + 3] & 0xC0) === 0x80) {
          utf8Score += 4;
          i += 4;
          continue;
        }
      }
      
      // GBK/GB18030 双字节检测
      if (b >= 0x81 && b <= 0xFE && i + 1 < len) {
        const b2 = bytes[i + 1];
        // GBK 第二字节范围
        if ((b2 >= 0x40 && b2 <= 0x7E) || (b2 >= 0x80 && b2 <= 0xFE)) {
          gbkScore += 2;
          i += 2;
          continue;
        }
      }
      
      // 无法识别的字节
      i++;
    }
    
    logger.info(TAG, `编码检测得分: UTF-8=${utf8Score}, GBK/GB18030=${gbkScore}`);
    
    // 根据得分判断编码
    if (utf8Score > gbkScore * 1.5) {
      return 'utf-8';
    } else if (gbkScore > 0) {
      // 优先使用 GB18030，它是 GBK 的超集
      return 'gb18030';
    }
    
    // 默认使用 UTF-8
    return 'utf-8';
  }
  
  /**
   * 检查文本是否包含乱码
   */
  private hasGarbledText(text: string): boolean {
    // 检查是否包含常见的乱码特征
    const garbledPatterns = [
      /\ufffd{2,}/,           // 连续的替换字符
      /[\x00-\x08\x0B\x0C\x0E-\x1F]{3,}/, // 连续的控制字符
    ];
    
    for (const pattern of garbledPatterns) {
      if (pattern.test(text)) {
        return true;
      }
    }
    
    // 检查前 1000 个字符中是否有过多的替换字符
    const sample = text.substring(0, 1000);
    const replacementCount = (sample.match(/\ufffd/g) || []).length;
    if (replacementCount > 10) {
      return true;
    }
    
    return false;
  }

  /**
   * 获取文件大小
   */
  private async getFileSize(): Promise<number> {
    try {
      let openTarget: string = this.filePath;
      if (!this.filePath.startsWith('file://') && !this.filePath.startsWith('/')) {
        openTarget = `/${this.filePath}`;
      }

      let file = fileIo.openSync(openTarget, fileIo.OpenMode.READ_ONLY);
      let stat = fileIo.statSync(file.fd);
      fileIo.closeSync(file);
      return stat.size;
    } catch (firstError) {
      try {
        if (this.filePath.startsWith('file://')) {
          const stripped = this.filePath.substring(7);
          const candidate = stripped.startsWith('/') ? stripped : `/${stripped}`;
          const file = fileIo.openSync(candidate, fileIo.OpenMode.READ_ONLY);
          const stat = fileIo.statSync(file.fd);
          fileIo.closeSync(file);
          return stat.size;
        }
        return 0;
      } catch (error) {
        logger.warn(TAG, `获取文件大小失败: ${String(error instanceof Error ? error.message : error)}`);
        return 0;
      }
    }
  }

  /**
   * 从文件名提取标签
   */
  private extractTagsFromFileName(fileName: string): string[] {
    const tags: string[] = ['TXT'];
    const tagKeywords = ['玄幻', '都市', '言情', '科幻', '武侠', '仙侠', '历史', '军事', '网游', '竞技', '灵异', '同人'];
    for (const keyword of tagKeywords) {
      if (fileName.includes(keyword)) {
        tags.push(keyword);
      }
    }
    return tags;
  }

  /**
   * 分割章节
   */
  private splitIntoChapters(content: string, bookId: string): EBookChapter[] {
    const chapters: EBookChapter[] = [];
    const lines = content.split('\n');
    
    let currentChapterTitle = '正文';
    let currentChapterNumber = 0;
    let currentChapterLines: string[] = [];
    let startPosition = 0;
    const now = Date.now();

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmed = line.trim();
      
      let matchedChapter: RegExpMatchArray | null = null;
      for (const pattern of CHAPTER_PATTERNS) {
        const match = trimmed.match(pattern);
        if (match) {
          matchedChapter = match;
          break;
        }
      }

      if (matchedChapter && currentChapterLines.length > 0) {
        const chapterContent = currentChapterLines.join('\n').trim();
        if (chapterContent.length > 0) {
          const chapter: EBookChapter = {
            id: `${bookId}_chapter_${currentChapterNumber}`,
            bookId: bookId,
            chapterNumber: currentChapterNumber,
            title: currentChapterTitle,
            content: chapterContent,
            startPosition: startPosition,
            endPosition: startPosition + chapterContent.length,
            wordCount: this.countWords(chapterContent),
            createTime: now
          };
          chapters.push(chapter);
          currentChapterNumber++;
        }

        currentChapterTitle = trimmed;
        currentChapterLines = [];
        startPosition += chapterContent.length + 1;
      } else {
        currentChapterLines.push(line);
      }
    }

    if (currentChapterLines.length > 0) {
      const chapterContent = currentChapterLines.join('\n').trim();
      if (chapterContent.length > 0) {
        const chapter: EBookChapter = {
          id: `${bookId}_chapter_${currentChapterNumber}`,
          bookId: bookId,
          chapterNumber: currentChapterNumber,
          title: currentChapterTitle,
          content: chapterContent,
          startPosition: startPosition,
          endPosition: startPosition + chapterContent.length,
          wordCount: this.countWords(chapterContent),
          createTime: now
        };
        chapters.push(chapter);
      }
    }

    if (chapters.length === 0) {
      const fullContent = content.trim();
      const chapter: EBookChapter = {
        id: `${bookId}_chapter_0`,
        bookId: bookId,
        chapterNumber: 0,
        title: '正文',
        content: fullContent,
        startPosition: 0,
        endPosition: fullContent.length,
        wordCount: this.countWords(fullContent),
        createTime: now
      };
      chapters.push(chapter);
    }

    logger.info(TAG, `识别到 ${chapters.length} 个章节`);
    return chapters;
  }

  private countWords(text: string): number {
    return text.replace(/\s/g, '').length;
  }

  private calculateTotalWordCount(chapters: EBookChapter[]): number {
    let total = 0;
    for (const chapter of chapters) {
      total += chapter.wordCount;
    }
    return total;
  }
}

/**
 * 注意：EPUB、MOBI、AZW/AZW3 格式现在由 ReaderKitEBookParser 处理
 * 这些类已被 Reader Kit 官方 API 替代
 * 
 * Reader Kit 支持的格式：
 * - EPUB: 使用 Reader Kit 解析
 * - MOBI: 使用 Reader Kit 解析
 * - AZW/AZW3: 使用 Reader Kit 解析
 * 
 * 参考 ReaderKitParser.ets 文件
 */

/**
 * PDF解析器实现
 * 使用 PDF Kit 获取文档信息（页数、元数据等）
 * 阅读时使用 PdfView 组件进行预览
 */
class PdfParser extends EBookParser {
  constructor(filePath: string) {
    super(filePath, EBookFormat.PDF);
  }

  public async parse(): Promise<EBook> {
    logger.info(TAG, `开始解析PDF文件: ${this.filePath}`);
    
    const fileName = this.getFileNameFromPath(this.filePath);
    const title = this.extractTitleFromFileName(fileName);
    
    // 使用 PDF Kit 获取文档信息
    let pageCount = 0;
    let fileSize = 0;
    let pdfMetadata: PdfDocumentMetadata = {
      title: '',
      author: '',
      subject: '',
      keywords: '',
      creator: '',
      producer: ''
    };
    
    try {
      const pdfInfo = await this.parsePdfWithKit();
      pageCount = pdfInfo.pageCount;
      fileSize = pdfInfo.fileSize;
      pdfMetadata = pdfInfo.metadata;
      logger.info(TAG, `PDF Kit 解析成功: 页数=${pageCount}, 文件大小=${fileSize}`);
    } catch (error) {
      logger.warn(TAG, `PDF Kit 解析失败，使用默认值: ${String(error)}`);
    }
    
    // 创建元数据（优先使用 PDF Kit 解析的信息）
    const metadata: EBookMetadata = {
      title: pdfMetadata.title || title,
      author: pdfMetadata.author || '未知作者',
      publisher: pdfMetadata.producer || '',
      publishDate: '',
      isbn: '',
      language: 'zh-CN',
      description: pdfMetadata.subject || `PDF文档，共 ${pageCount} 页`,
      coverImagePath: '',
      tags: ['PDF'],
      rating: 0
    };
    
    const ebook = this.generateDefaultEBook(this.filePath, EBookFormat.PDF, metadata);
    ebook.fileSize = fileSize;
    
    // 为每一页创建一个"章节"（用于进度跟踪）
    const now = Date.now();
    if (pageCount > 0) {
      for (let i = 0; i < pageCount; i++) {
        const chapter: EBookChapter = {
          id: `pdf_page_${ebook.id}_${i}`,
          bookId: ebook.id,
          title: `第 ${i + 1} 页`,
          content: '', // PDF 不存储内容，由 PdfView 组件渲染
          chapterNumber: i + 1,
          wordCount: 0,
          startPosition: i,
          endPosition: i + 1,
          createTime: now
        };
        ebook.chapters.push(chapter);
      }
    } else {
      // 如果无法获取页数，创建单个章节
      const chapter: EBookChapter = {
        id: `pdf_chapter_${now}`,
        bookId: ebook.id,
        title: '全文',
        content: '',
        chapterNumber: 1,
        wordCount: 0,
        startPosition: 0,
        endPosition: 0,
        createTime: now
      };
      ebook.chapters.push(chapter);
    }
    
    logger.info(TAG, `PDF文件解析完成: ${metadata.title}，共 ${pageCount} 页`);
    return ebook;
  }

  /**
   * 使用 PDF Kit 解析 PDF 文档
   */
  private async parsePdfWithKit(): Promise<PdfParseResult> {
    try {
      logger.info(TAG, `[PDF Kit] 开始解析: ${this.filePath}`);
      
      // 创建 PdfDocument 对象
      const pdfDocument = new pdfService.PdfDocument();
      
      // 加载文档
      const loadResult = pdfDocument.loadDocument(this.filePath);
      logger.info(TAG, `[PDF Kit] 加载结果: ${JSON.stringify(loadResult)}`);
      
      // 获取页数
      const pageCount = pdfDocument.getPageCount();
      logger.info(TAG, `[PDF Kit] 页数: ${pageCount}`);
      
      // 获取文件大小
      let fileSize = 0;
      try {
        const stat = fileIo.statSync(this.filePath);
        fileSize = stat.size;
      } catch (e) {
        logger.warn(TAG, `获取文件大小失败: ${e}`);
      }
      
      // 获取第一页信息（用于验证）
      let firstPageWidth = 0;
      let firstPageHeight = 0;
      if (pageCount > 0) {
        try {
          const firstPage = pdfDocument.getPage(0);
          firstPageWidth = firstPage.getWidth();
          firstPageHeight = firstPage.getHeight();
          logger.info(TAG, `[PDF Kit] 第一页尺寸: ${firstPageWidth} x ${firstPageHeight}`);
        } catch (e) {
          logger.warn(TAG, `获取第一页信息失败: ${e}`);
        }
      }
      
      // 尝试获取文档元数据（PDF Kit 可能不支持直接获取元数据）
      const metadata: PdfDocumentMetadata = {
        title: '',
        author: '',
        subject: '',
        keywords: '',
        creator: '',
        producer: ''
      };
      
      return {
        pageCount,
        fileSize,
        firstPageWidth,
        firstPageHeight,
        metadata
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `[PDF Kit] 解析失败: ${errorMsg}`);
      throw error as Error;
    }
  }
}

/**
 * PDF 文档元数据接口
 */
interface PdfDocumentMetadata {
  title: string;
  author: string;
  subject: string;
  keywords: string;
  creator: string;
  producer: string;
}

/**
 * PDF 解析结果接口
 */
interface PdfParseResult {
  pageCount: number;
  fileSize: number;
  firstPageWidth: number;
  firstPageHeight: number;
  metadata: PdfDocumentMetadata;
}
