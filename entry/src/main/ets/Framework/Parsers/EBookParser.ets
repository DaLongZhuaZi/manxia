// 文件路径: entry/src/main/ets/Framework/Parsers/EBookParser.ets
/**
 * 电子书解析器基类
 * 提供统一的电子书解析接口
 */

import { EBook, EBookFormat, EBookMetadata, EBookChapter, EBookStatus, EBookPageMode } from '../../Models/EBookModels';
import { logger } from '../../Utils/Logger';
import { ReaderKitEBookParser } from './ReaderKitParser';

const TAG = 'EBookParser';

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
  public static createParser(filePath: string): EBookParser | ReaderKitEBookParser | null {
    const format = EBookParserFactory.detectFormat(filePath);
    
    if (!format) {
      logger.warn(TAG, `无法识别的电子书格式: ${filePath}`);
      return null;
    }

    // 对于 Reader Kit 支持的格式，使用官方 API
    if (ReaderKitEBookParser.isSupportedFormat(format) && format !== EBookFormat.TXT) {
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
        logger.warn(TAG, `不支持的电子书格式: ${filePath}`);
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
  constructor(filePath: string) {
    super(filePath, EBookFormat.TXT);
  }

  public async parse(): Promise<EBook> {
    logger.info(TAG, `开始解析TXT文件: ${this.filePath}`);
    
    // 这里需要实现TXT文件的读取和解析逻辑
    // 由于HarmonyOS的文件读取API，我们需要在具体实现时补充
    
    const fileName = this.getFileNameFromPath(this.filePath);
    const title = this.extractTitleFromFileName(fileName);
    
    const metadata: EBookMetadata = {
      title: title,
      author: '未知作者',
      publisher: '',
      publishDate: '',
      isbn: '',
      language: 'zh-CN',
      description: '',
      coverImagePath: '',
      tags: ['TXT'],
      rating: 0
    };
    
    const ebook = this.generateDefaultEBook(this.filePath, EBookFormat.TXT, metadata);
    
    // TODO: 实际解析章节内容
    // 这里需要读取文件内容，识别章节分隔符，拆分成章节
    
    logger.info(TAG, `TXT文件解析完成: ${title}`);
    return ebook;
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
 * 注意：PDF解析采用Web组件预览方案，不进行深度内容解析
 */
class PdfParser extends EBookParser {
  constructor(filePath: string) {
    super(filePath, EBookFormat.PDF);
  }

  public async parse(): Promise<EBook> {
    logger.info(TAG, `开始解析PDF文件: ${this.filePath}`);
    
    const fileName = this.getFileNameFromPath(this.filePath);
    const title = this.extractTitleFromFileName(fileName);
    
    // 创建元数据
    const metadata: EBookMetadata = {
      title: title,
      author: '未知作者',
      publisher: '',
      publishDate: '',
      isbn: '',
      language: 'zh-CN',
      description: 'PDF文档，点击开始阅读按钮可预览内容',
      coverImagePath: '',
      tags: ['PDF'],
      rating: 0
    };
    
    const ebook = this.generateDefaultEBook(this.filePath, EBookFormat.PDF, metadata);
    
    // 添加单个章节（整个PDF作为一个章节）
    const now = Date.now();
    const chapter: EBookChapter = {
      id: `pdf_chapter_${now}`,
      bookId: ebook.id,
      title: '全文',
      content: this.filePath, // 存储PDF文件路径，用于Web组件加载
      chapterNumber: 1,
      wordCount: 0,
      startPosition: 0,
      endPosition: 0,
      createTime: now
    };
    ebook.chapters.push(chapter);
    
    logger.info(TAG, `PDF文件解析完成: ${title}，将使用Web组件进行预览`);
    return ebook;
  }
}
