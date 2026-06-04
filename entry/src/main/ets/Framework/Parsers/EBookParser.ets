import { SafeFileUtils } from '../../Utils/SafeFileUtils';
// 文件路径: entry/src/main/ets/Framework/Parsers/EBookParser.ets
/**
 * 电子书解析器基类
 * 提供统一的电子书解析接口
 */

import {
  EBook,
  EBookFormat,
  EBookMetadata,
  EBookChapter,
  EpubNavigationItem,
  EBookStatus,
  EBookPageMode,
  EBookContentMode,
  EBookReaderEngine
} from '../../Models/EBookModels';
import { logger } from '../../Utils/Logger';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { pdfService } from '@kit.PDFKit';
import { bookParser } from '@kit.ReaderKit';
import { zlib } from '@kit.BasicServicesKit';
import { TxtMetadataExtractor } from './TxtMetadataExtractor';
import { isReaderKitEnabled } from '../Initialization/ReaderKitFeatureGate';
import { convertMobiToExtractedDir } from './MobiParser';

const TAG = 'EBookParser';
const EPUB_IMAGE_RESOURCE_PATTERN = /<(?:img|image)\b[^>]+(?:src|href|xlink:href)\s*=\s*["']([^"']+)["']/ig;
const EPUB_CONTAINER_FULL_PATH_PATTERN = /full-path\s*=\s*["']([^"']+)["']/i;
const EPUB_FIXED_LAYOUT_PATTERN = /(pre-paginated|rendition:layout[^"'<>]*["'>\s:=]+pre-paginated)/i;

interface EpubManifestItem {
  href: string;
  mediaType: string;
  properties?: string;
}

interface EpubHrefLocation {
  resourcePath: string;
  fragment: string;
}

interface GeneratedNavigationScanResult {
  items: EpubNavigationItem[];
  htmlText: string;
  changed: boolean;
}

function isReaderKitUnavailableError(message: string): boolean {
  const normalized = message.toLowerCase();
  return normalized.includes('reader kit is unavailable in current environment') ||
    normalized.includes('reader kit unavailable') ||
    (normalized.includes('reader kit') && normalized.includes('unavailable')) ||
    normalized.includes('bookparser is missing') ||
    normalized.includes('bookparser missing') ||
    normalized.includes('bookparserhandler') ||
    normalized.includes('failed to lazy-load reader kit') ||
    (normalized.includes('cannot find module') && normalized.includes('@kit.readerkit'));
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
      const errorMsg = String(error instanceof Error ? error.message : error);
      if (isReaderKitUnavailableError(errorMsg)) {
        logger.warn(TAG, `Reader Kit unavailable, fallback parser will be used: ${errorMsg}`);
      } else {
        logger.error(TAG, `Reader Kit 解析失败: ${errorMsg}`);
      }
      return this.parseFallback();
    }
  }

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
          return buffer;
        }
        throw new Error(firstMsg);
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        throw new Error(`文件读取失败: ${errorMsg}`);
      }
    }
  }

  private async parseWithReaderKit(_fileBuffer: ArrayBuffer): Promise<ReaderKitBookInfo> {
    try {
      const fileName = this.getFileNameFromPath(this.filePath);
      const candidatePath: string = this.filePath;
      logger.info(TAG, `[ReaderKit] 开始解析，路径: ${candidatePath}`);
      
      if (!isReaderKitEnabled()) {
        throw new Error('Reader Kit is unavailable in current environment');
      }
      const parserHandler: bookParser.BookParserHandler =
        await createReaderKitBookParserHandler(candidatePath, 'parseWithReaderKit');
      if (!parserHandler) {
        throw new Error('无法获取 BookParserHandler');
      }
      logger.info(TAG, `[ReaderKit] Handler 获取成功`);

      // 获取书籍信息 - 使用 Object 类型转换以访问动态属性
      const rawInfo = parserHandler.getBookInfo();
      logger.info(TAG, `[ReaderKit] BookInfo 原始数据: ${this.safeStringify(rawInfo)}`);
      const infoObj = this.normalizeToRecord(rawInfo);
      
      // 打印所有可用的属性键，帮助调试
      const allKeys = Object.keys(infoObj);
      logger.info(TAG, `[ReaderKit] BookInfo 所有属性键: ${allKeys.length > 0 ? allKeys.join(', ') : '(empty)'}`);
      
      // 获取目录
      const rawCatalog = parserHandler.getCatalogList();
      const catalogArray = this.extractCatalogEntries(rawCatalog);
      logger.info(TAG, `[ReaderKit] 目录数量: ${catalogArray?.length || 0}`);
      if (catalogArray && catalogArray.length > 0) {
        logger.info(TAG, `[ReaderKit] 第一个目录项: ${this.safeStringify(catalogArray[0])}`);
      }

      // 构建章节列表
      let chapters: ReaderKitChapter[] = this.buildChaptersFromCatalog(catalogArray);
      if (chapters.length <= 0) {
        let chapterCount = this.getNumberProperty(infoObj, ['chapterCount', 'catalogCount', 'resourceCount', 'spineCount']);
        if (chapterCount <= 0) {
          chapterCount = this.getNumberPropertyByPartialKey(infoObj, ['chapter', 'catalog', 'resource', 'spine', 'count']);
        }
        if (chapterCount <= 0 && catalogArray.length > 1) {
          chapterCount = catalogArray.length;
        }
        if (chapterCount > 0) {
          chapters = this.buildSyntheticChapters(chapterCount);
          logger.info(TAG, `[ReaderKit] 目录缺失，使用章节数量字段创建占位目录: count=${chapterCount}`);
        }
      }
      
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
      const author = this.getStringProperty(infoObj, ['bookCreator', 'author', 'creator', 'bookAuthor']) ||
        this.getStringPropertyByPartialKey(infoObj, ['author', 'creator', 'writer']);
      const publisher = this.getStringProperty(infoObj, ['bookPublisher', 'publisher', 'press']) ||
        this.getStringPropertyByPartialKey(infoObj, ['publisher', 'press']);
      const description = this.getStringProperty(infoObj, ['bookDescription', 'description', 'desc', 'summary', 'intro']) ||
        this.getStringPropertyByPartialKey(infoObj, ['description', 'summary', 'intro', 'abstract']);
      const title = this.getStringProperty(infoObj, ['bookTitle', 'title', 'name', 'bookName']) ||
        this.getStringPropertyByPartialKey(infoObj, ['title', 'bookname', 'name']) ||
        this.extractTitleFromFileName(fileName);
      const publishDate = this.getStringProperty(infoObj, ['bookPublishDate', 'publishDate', 'pubDate', 'date']) ||
        this.getStringPropertyByPartialKey(infoObj, ['publishdate', 'pubdate', 'issuedate', 'date']);
      const isbn = this.getStringProperty(infoObj, ['bookIsbn', 'isbn', 'ISBN']) ||
        this.getStringPropertyByPartialKey(infoObj, ['isbn']);
      const language = this.getStringProperty(infoObj, ['bookLanguage', 'language', 'lang']) ||
        this.getStringPropertyByPartialKey(infoObj, ['language', 'lang']) ||
        'zh-CN';
      const coverImagePath = this.getStringProperty(infoObj, ['bookCoverImage', 'coverUrl', 'cover', 'coverPath', 'coverImage']) ||
        this.getStringPropertyByPartialKey(infoObj, ['cover', 'thumbnail', 'image']);
      
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
      
      const contentAnalysis = await this.analyzeReaderKitContentMode(chapters, infoObj);
      const bookInfo: ReaderKitBookInfo = {
        title: title,
        author: author || '未知作者',
        publisher: publisher,
        publishDate: publishDate || '',
        isbn: isbn || '',
        language: language,
        description: description || `${this.format} 电子书`,
        coverImagePath: coverImagePath || '',
        chapters: contentAnalysis.chapters,
        contentMode: contentAnalysis.contentMode,
        preferredReaderEngine: contentAnalysis.preferredReaderEngine,
        extractedRootPath: contentAnalysis.extractedRootPath
      };
      
      logger.info(TAG, `[ReaderKit] 解析完成: 书名=${bookInfo.title}, 作者=${bookInfo.author}, 出版社=${bookInfo.publisher}, 简介长度=${bookInfo.description.length}, 章节数=${chapters.length}`);
      return bookInfo;
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      if (isReaderKitUnavailableError(errorMsg)) {
        if (error instanceof Error) throw error;
        throw new Error(String(error));
      }
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

  private normalizeToRecord(raw: Object): Record<string, Object> {
    if (!raw || typeof raw !== 'object') {
      const emptyRecord: Record<string, Object> = {};
      return emptyRecord;
    }
    return raw as Record<string, Object>;
  }

  private safeStringify(raw: Object): string {
    try {
      return JSON.stringify(raw);
    } catch {
      return '[unserializable]';
    }
  }

  private getStringPropertyByPartialKey(obj: Record<string, Object>, keyFragments: string[]): string {
    const keys = Object.keys(obj);
    for (let index = 0; index < keys.length; index++) {
      const key = keys[index];
      const value = obj[key];
      const normalizedKey = key.toLowerCase();
      const keyMatched = keyFragments.some((fragment: string) => normalizedKey.includes(fragment.toLowerCase()));
      if (!keyMatched || value === undefined || value === null) {
        continue;
      }
      const text = String(value).trim();
      if (text.length > 0) {
        return text;
      }
    }
    return '';
  }

  private getNumberProperty(obj: Record<string, Object>, keys: string[]): number {
    for (const key of keys) {
      const value = obj[key];
      if (typeof value === 'number' && Number.isFinite(value) && value >= 0) {
        return Math.floor(value);
      }
      if (typeof value === 'string') {
        const parsed = Number(value);
        if (Number.isFinite(parsed) && parsed >= 0) {
          return Math.floor(parsed);
        }
      }
    }
    return -1;
  }

  private getNumberPropertyByPartialKey(obj: Record<string, Object>, keyFragments: string[]): number {
    const keys = Object.keys(obj);
    for (let index = 0; index < keys.length; index++) {
      const key = keys[index];
      const value = obj[key];
      const normalizedKey = key.toLowerCase();
      const keyMatched = keyFragments.some((fragment: string) => normalizedKey.includes(fragment.toLowerCase()));
      if (!keyMatched) {
        continue;
      }
      if (typeof value === 'number' && Number.isFinite(value) && value >= 0) {
        return Math.floor(value);
      }
      if (typeof value === 'string') {
        const parsed = Number(value);
        if (Number.isFinite(parsed) && parsed >= 0) {
          return Math.floor(parsed);
        }
      }
    }
    return -1;
  }

  private isCatalogEntryCandidate(item: Record<string, Object>): boolean {
    const possibleKeys = ['catalogId', 'id', 'chapterId', 'href', 'resourceFile', 'catalogName', 'title', 'name', 'chapterTitle'];
    for (const key of possibleKeys) {
      if (item[key] !== undefined && item[key] !== null) {
        return true;
      }
    }
    return false;
  }

  private extractCatalogEntries(rawCatalog: Object): Array<Record<string, Object>> {
    const result: Array<Record<string, Object>> = [];
    const seen: Set<string> = new Set();
    const visitedNodes: Set<Object> = new Set();

    if (!rawCatalog || typeof rawCatalog !== 'object') {
      return result;
    }

    const flattenNodes = (nodes: Array<Record<string, Object>>): void => {
      const stack: Array<Record<string, Object>> = [...nodes];
      while (stack.length > 0) {
        const item = stack.shift();
        if (!item) {
          continue;
        }
        if (visitedNodes.has(item as Object)) {
          continue;
        }
        visitedNodes.add(item as Object);

        const chapterId = this.getStringProperty(item, ['catalogId', 'id', 'chapterId', 'href', 'resourceFile', 'resourceId', 'spineIndex', 'index']) ||
          this.getStringPropertyByPartialKey(item, ['catalogid', 'chapterid', 'resource', 'spine', 'index', 'href']);
        const chapterTitle = this.getStringProperty(item, ['catalogName', 'title', 'name', 'chapterTitle', 'label', 'text']) ||
          this.getStringPropertyByPartialKey(item, ['catalogname', 'chaptertitle', 'title', 'name', 'label', 'text']);

        if (chapterTitle.length > 0 || chapterId.length > 0 || this.isCatalogEntryCandidate(item)) {
          const dedupeKey = (chapterId.length > 0 || chapterTitle.length > 0)
            ? `${chapterId}::${chapterTitle}`
            : this.safeStringify(item);
          if (!seen.has(dedupeKey)) {
            seen.add(dedupeKey);
            result.push(item);
          }
        }
        const childKeys = [
          'children',
          'subCatalogs',
          'subCatalogList',
          'subCatalog',
          'subItems',
          'subChapter',
          'catalogList',
          'items',
          'chapters',
          'tocList',
          'toc',
          'contentList',
          'childCatalog',
          'childList'
        ];
        for (const childKey of childKeys) {
          const child = item[childKey];
          if (Array.isArray(child)) {
            const childArray = child as Object[];
            for (let childIndex = 0; childIndex < childArray.length; childIndex++) {
              const childItem = childArray[childIndex];
              if (childItem && typeof childItem === 'object') {
                stack.push(childItem as Record<string, Object>);
              }
            }
          }
        }
      }
    };

    if (Array.isArray(rawCatalog)) {
      flattenNodes(rawCatalog as Array<Record<string, Object>>);
      return result;
    }

    const rawCatalogObj = this.normalizeToRecord(rawCatalog);
    if (this.isCatalogEntryCandidate(rawCatalogObj)) {
      flattenNodes([rawCatalogObj]);
    }
    const topLevelKeys = [
      'catalogList',
      'catalogs',
      'items',
      'children',
      'toc',
      'tocList',
      'chapterList',
      'chapters',
      'subCatalogs',
      'subCatalogList'
    ];
    for (const key of topLevelKeys) {
      const value = rawCatalogObj[key];
      if (Array.isArray(value)) {
        flattenNodes(value as Array<Record<string, Object>>);
      }
    }
    if (result.length > 0) {
      return result;
    }

    const rawCatalogKeys = Object.keys(rawCatalogObj);
    for (let keyIndex = 0; keyIndex < rawCatalogKeys.length; keyIndex++) {
      const rawCatalogKey = rawCatalogKeys[keyIndex];
      const value = rawCatalogObj[rawCatalogKey];
      if (Array.isArray(value)) {
        flattenNodes(value as Array<Record<string, Object>>);
      } else if (value && typeof value === 'object') {
        const nestedObj = value as Record<string, Object>;
        if (this.isCatalogEntryCandidate(nestedObj)) {
          flattenNodes([nestedObj]);
        }
      }
    }
    return result;
  }

  private buildSyntheticChapters(chapterCount: number): ReaderKitChapter[] {
    const safeCount = Math.max(0, chapterCount);
    const chapters: ReaderKitChapter[] = [];
    for (let i = 0; i < safeCount; i++) {
      chapters.push({
        id: `resource_${i}`,
        title: `第${i + 1}章`,
        content: ''
      });
    }
    return chapters;
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
      const chapterId = this.getStringProperty(item, ['catalogId', 'id', 'chapterId', 'href', 'resourceFile', 'resourceId', 'index']) ||
        this.getStringPropertyByPartialKey(item, ['catalogid', 'chapterid', 'resource', 'spine', 'index', 'href']) ||
        `resource_${i}`;
      const chapterTitle = this.getStringProperty(item, ['catalogName', 'title', 'name', 'chapterTitle', 'label']) ||
        this.getStringPropertyByPartialKey(item, ['catalogname', 'chaptertitle', 'title', 'name', 'label']) ||
        `第${i + 1}章`;
      const resourceHref = this.getStringProperty(item, ['href', 'resourceHref']) ||
        this.getStringPropertyByPartialKey(item, ['href']);
      const resourceFile = this.getStringProperty(item, ['resourceFile', 'file', 'src']) ||
        this.getStringPropertyByPartialKey(item, ['resourcefile']);
      const ch: ReaderKitChapter = {
        id: chapterId,
        title: chapterTitle,
        content: '',
        resourceHref: resourceHref,
        resourceFile: resourceFile,
        resourceMediaType: this.inferMediaTypeFromPath(resourceFile || resourceHref),
        resourceLayoutType: 'UNKNOWN'
      };
      chapters.push(ch);
    }
    return chapters;
  }

  private async analyzeReaderKitContentMode(
    chapters: ReaderKitChapter[],
    infoObj: Record<string, Object>
  ): Promise<ReaderKitContentAnalysis> {
    const defaultContentMode = this.format === EBookFormat.EPUB
      ? EBookContentMode.REFLOWABLE_TEXT
      : EBookContentMode.UNKNOWN;
    const fallback: ReaderKitContentAnalysis = {
      chapters: chapters,
      contentMode: defaultContentMode,
      preferredReaderEngine: EBookReaderEngine.READER_KIT,
      extractedRootPath: ''
    };
    if (this.format !== EBookFormat.EPUB || chapters.length <= 0) {
      return fallback;
    }

    try {
      const extractedRootPath = await this.ensureEpubExtractionRoot();
      if (extractedRootPath.length <= 0) {
        return fallback;
      }

      const opfPath = this.resolveEpubPackageDocumentPath(extractedRootPath);
      const packageRoot = opfPath.length > 0 ? this.getParentDir(opfPath) : extractedRootPath;
      const opfText = (opfPath.length > 0 && this.pathExists(opfPath)) ? this.readTextFileSync(opfPath) : '';
      const enhancedChapters: ReaderKitChapter[] = chapters.map((chapter: ReaderKitChapter) => {
        return this.enrichEpubChapterResource(chapter, packageRoot, extractedRootPath);
      });

      let imageChapterCount = 0;
      for (const chapter of enhancedChapters) {
        if ((chapter.resourceImagePath || '').length > 0) {
          imageChapterCount++;
        }
      }

      const imageRatio = enhancedChapters.length > 0 ? imageChapterCount / enhancedChapters.length : 0;
      if (imageChapterCount >= 3 && imageRatio >= 0.6) {
        for (const chapter of enhancedChapters) {
          if (!chapter.resourceLayoutType || chapter.resourceLayoutType === 'UNKNOWN' || chapter.resourceLayoutType === 'TEXT_HTML') {
            chapter.resourceLayoutType = 'IMAGE_PAGE';
          }
        }
        logger.info(TAG, `[ReaderKit] 检测到图片页 EPUB: imageChapters=${imageChapterCount}, total=${enhancedChapters.length}, ratio=${imageRatio.toFixed(2)}`);
        return {
          chapters: enhancedChapters,
          contentMode: EBookContentMode.IMAGE_PAGE,
          preferredReaderEngine: EBookReaderEngine.MANGA,
          extractedRootPath: extractedRootPath
        };
      }

      if (this.isFixedLayoutEpub(infoObj, opfText)) {
        logger.info(TAG, '[ReaderKit] 检测到固定版式 EPUB，使用 WebView 引擎渲染');
        return {
          chapters: enhancedChapters,
          contentMode: EBookContentMode.FIXED_LAYOUT_HTML,
          preferredReaderEngine: EBookReaderEngine.WEBVIEW,
          extractedRootPath: extractedRootPath
        };
      }

      return {
        chapters: enhancedChapters,
        contentMode: EBookContentMode.REFLOWABLE_TEXT,
        preferredReaderEngine: EBookReaderEngine.READER_KIT,
        extractedRootPath: extractedRootPath
      };
    } catch (error) {
      logger.warn(TAG, `[ReaderKit] EPUB 内容模式分析失败，回退为普通文本 EPUB: ${String(error)}`);
      return fallback;
    }
  }

  public async getExtractionRoot(): Promise<string> {
    try {
      return await this.ensureEpubExtractionRoot();
    } catch (e) {
      logger.warn(TAG, `[ReaderKit] 懒提取失败: ${String(e)}`);
      return '';
    }
  }

  private extractXmlAttribute(attrsText: string, attrName: string): string {
    const pattern = new RegExp(`\\b${attrName}\\s*=\\s*["']([^"']+)["']`, 'i');
    const match = attrsText.match(pattern);
    return match && match[1] ? String(match[1]).trim() : '';
  }

  private parseOpfManifestItems(opfText: string): Map<string, EpubManifestItem> {
    const manifestItems = new Map<string, EpubManifestItem>();
    const manifestSectionMatch = opfText.match(/<manifest\b[\s\S]*?<\/manifest>/i);
    const manifestText = manifestSectionMatch ? manifestSectionMatch[0] : opfText;
    const manifestPattern = /<item\b([^>]*?)\/?>/gi;
    let manifestMatch = manifestPattern.exec(manifestText);
    while (manifestMatch !== null) {
      const attrs = manifestMatch[1] ?? '';
      const id = this.extractXmlAttribute(attrs, 'id');
      const href = this.extractXmlAttribute(attrs, 'href');
      const mediaType = this.extractXmlAttribute(attrs, 'media-type');
      const properties = this.extractXmlAttribute(attrs, 'properties');
      if (id.length > 0 && href.length > 0) {
        const manifestItem: EpubManifestItem = {
          href: href,
          mediaType: mediaType,
          properties: properties
        };
        manifestItems.set(id, manifestItem);
      }
      manifestMatch = manifestPattern.exec(manifestText);
    }
    return manifestItems;
  }

  private parseOpfSpineIds(opfText: string): string[] {
    const spineIds: string[] = [];
    const spineSectionMatch = opfText.match(/<spine\b[\s\S]*?<\/spine>/i);
    const spineText = spineSectionMatch ? spineSectionMatch[0] : opfText;
    const spinePattern = /<itemref\b[^>]+idref\s*=\s*["']([^"']+)["'][^>]*\/?>/gi;
    let spineMatch = spinePattern.exec(spineText);
    while (spineMatch !== null) {
      spineIds.push(String(spineMatch[1] ?? '').trim());
      spineMatch = spinePattern.exec(spineText);
    }
    return spineIds;
  }

  private decodeXmlText(text: string): string {
    return text
      .replace(/&nbsp;/ig, ' ')
      .replace(/&amp;/ig, '&')
      .replace(/&lt;/ig, '<')
      .replace(/&gt;/ig, '>')
      .replace(/&quot;/ig, '"')
      .replace(/&#39;/ig, '\'')
      .replace(/&apos;/ig, '\'')
      .replace(/\s+/g, ' ')
      .trim();
  }

  private stripXmlTags(text: string): string {
    return this.decodeXmlText(
      text
        .replace(/<script[\s\S]*?<\/script>/ig, ' ')
        .replace(/<style[\s\S]*?<\/style>/ig, ' ')
        .replace(/<[^>]+>/g, ' ')
    );
  }

  private splitHrefLocation(rawHref: string): EpubHrefLocation {
    const trimmed = rawHref.trim();
    const hashIndex = trimmed.indexOf('#');
    if (hashIndex < 0) {
      return {
        resourcePath: this.normalizeRelativeResourcePath(trimmed),
        fragment: ''
      };
    }
    const resourcePath = this.normalizeRelativeResourcePath(trimmed.substring(0, hashIndex));
    const rawFragment = trimmed.substring(hashIndex + 1).trim();
    let decodedFragment = rawFragment;
    if (decodedFragment.length > 0) {
      try {
        decodedFragment = decodeURIComponent(decodedFragment);
      } catch (_error) {
        decodedFragment = rawFragment;
      }
    }
    return {
      resourcePath: resourcePath,
      fragment: decodedFragment
    };
  }

  private buildSpineHrefIndex(spineItems: EBookChapter[]): Map<string, number> {
    const indexMap = new Map<string, number>();
    for (let index = 0; index < spineItems.length; index++) {
      const chapter = spineItems[index];
      const resourceFile = this.normalizeRelativeResourcePath(chapter.resourceFile ?? '');
      const resourceHref = this.normalizeRelativeResourcePath(chapter.resourceHref ?? '');
      if (resourceFile.length > 0 && !indexMap.has(resourceFile)) {
        indexMap.set(resourceFile, index);
      }
      if (resourceHref.length > 0 && !indexMap.has(resourceHref)) {
        indexMap.set(resourceHref, index);
      }
    }
    return indexMap;
  }

  private findNavManifestItem(manifestItems: Map<string, EpubManifestItem>): EpubManifestItem | null {
    const values = Array.from(manifestItems.values());
    for (let index = 0; index < values.length; index++) {
      const item = values[index];
      const properties = (item.properties ?? '').toLowerCase();
      if (properties.includes('nav')) {
        return item;
      }
    }
    for (let index = 0; index < values.length; index++) {
      const item = values[index];
      const href = item.href.toLowerCase();
      if (href.includes('nav') && (href.endsWith('.xhtml') || href.endsWith('.html') || href.endsWith('.htm'))) {
        return item;
      }
    }
    return null;
  }

  private findNcxManifestItem(manifestItems: Map<string, EpubManifestItem>): EpubManifestItem | null {
    const values = Array.from(manifestItems.values());
    for (let index = 0; index < values.length; index++) {
      const item = values[index];
      const mediaType = item.mediaType.toLowerCase();
      const href = item.href.toLowerCase();
      if (mediaType === 'application/x-dtbncx+xml' || href.endsWith('.ncx')) {
        return item;
      }
    }
    return null;
  }

  private parseNavigationFromNavDocument(
    navDocPath: string,
    extractedRoot: string,
    spineIndexByHref: Map<string, number>
  ): EpubNavigationItem[] {
    const items: EpubNavigationItem[] = [];
    if (!this.pathExists(navDocPath)) {
      return items;
    }
    const navText = this.readTextFileSync(navDocPath);
    const baseDir = this.getParentDir(navDocPath);
    const tocNavMatch = navText.match(/<nav\b[^>]*(?:epub:type|type)\s*=\s*["'][^"']*\btoc\b[^"']*["'][^>]*>([\s\S]*?)<\/nav>/i);
    const fallbackNavMatch = navText.match(/<nav\b[^>]*>([\s\S]*?)<\/nav>/i);
    const navBlock = tocNavMatch && tocNavMatch[1]
      ? tocNavMatch[1]
      : (fallbackNavMatch && fallbackNavMatch[1] ? fallbackNavMatch[1] : '');
    if (navBlock.length <= 0) {
      return items;
    }
    const anchorPattern = /<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
    let anchorMatch = anchorPattern.exec(navBlock);
    let playOrder = 1;
    while (anchorMatch !== null) {
      const rawHref = String(anchorMatch[1] ?? '').trim();
      const title = this.stripXmlTags(String(anchorMatch[2] ?? ''));
      const hrefLocation = this.splitHrefLocation(rawHref);
      const absolutePath = hrefLocation.resourcePath.length > 0
        ? this.joinNormalizedPath(baseDir, hrefLocation.resourcePath)
        : '';
      const normalizedHref = absolutePath.length > 0
        ? this.normalizeRelativeResourcePath(this.buildRelativePath(extractedRoot, absolutePath))
        : '';
      const spineIndex = spineIndexByHref.has(normalizedHref)
        ? Number(spineIndexByHref.get(normalizedHref))
        : -1;
      if (title.length > 0 && normalizedHref.length > 0 && spineIndex >= 0) {
        items.push({
          id: `nav_${playOrder}_${normalizedHref}_${hrefLocation.fragment}`,
          title: title,
          href: rawHref,
          resourcePath: normalizedHref,
          fragment: hrefLocation.fragment,
          spineIndex: spineIndex,
          level: 0,
          playOrder: playOrder
        });
        playOrder++;
      }
      anchorMatch = anchorPattern.exec(navBlock);
    }
    return items;
  }

  private parseNavigationFromNcxDocument(
    ncxPath: string,
    extractedRoot: string,
    spineIndexByHref: Map<string, number>
  ): EpubNavigationItem[] {
    const items: EpubNavigationItem[] = [];
    if (!this.pathExists(ncxPath)) {
      return items;
    }
    const ncxText = this.readTextFileSync(ncxPath);
    const baseDir = this.getParentDir(ncxPath);
    const navPointPattern = /<navPoint\b[\s\S]*?<text\b[^>]*>([\s\S]*?)<\/text>[\s\S]*?<content\b[^>]*src\s*=\s*["']([^"']+)["'][^>]*\/?>/gi;
    let navPointMatch = navPointPattern.exec(ncxText);
    let playOrder = 1;
    while (navPointMatch !== null) {
      const title = this.stripXmlTags(String(navPointMatch[1] ?? ''));
      const rawHref = String(navPointMatch[2] ?? '').trim();
      const hrefLocation = this.splitHrefLocation(rawHref);
      const absolutePath = hrefLocation.resourcePath.length > 0
        ? this.joinNormalizedPath(baseDir, hrefLocation.resourcePath)
        : '';
      const normalizedHref = absolutePath.length > 0
        ? this.normalizeRelativeResourcePath(this.buildRelativePath(extractedRoot, absolutePath))
        : '';
      const spineIndex = spineIndexByHref.has(normalizedHref)
        ? Number(spineIndexByHref.get(normalizedHref))
        : -1;
      if (title.length > 0 && normalizedHref.length > 0 && spineIndex >= 0) {
        items.push({
          id: `ncx_${playOrder}_${normalizedHref}_${hrefLocation.fragment}`,
          title: title,
          href: rawHref,
          resourcePath: normalizedHref,
          fragment: hrefLocation.fragment,
          spineIndex: spineIndex,
          level: 0,
          playOrder: playOrder
        });
        playOrder++;
      }
      navPointMatch = navPointPattern.exec(ncxText);
    }
    return items;
  }

  private dedupeNavigationItems(items: EpubNavigationItem[]): EpubNavigationItem[] {
    const deduped: EpubNavigationItem[] = [];
    const seen: Set<string> = new Set();
    for (let index = 0; index < items.length; index++) {
      const item = items[index];
      const key = `${item.resourcePath}#${item.fragment}::${item.title}::${item.spineIndex}`;
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      deduped.push(item);
    }
    return deduped;
  }

  private parseNavigationFromManifest(
    extractedRoot: string,
    packageRoot: string,
    manifestItems: Map<string, EpubManifestItem>,
    spineItems: EBookChapter[]
  ): EpubNavigationItem[] {
    const spineIndexByHref = this.buildSpineHrefIndex(spineItems);
    if (spineIndexByHref.size <= 0) {
      return [];
    }

    let items: EpubNavigationItem[] = [];
    const navManifestItem = this.findNavManifestItem(manifestItems);
    if (navManifestItem) {
      const navPath = this.joinNormalizedPath(packageRoot, this.normalizeRelativeResourcePath(navManifestItem.href));
      items = this.parseNavigationFromNavDocument(navPath, extractedRoot, spineIndexByHref);
    }

    if (items.length <= 0) {
      const ncxManifestItem = this.findNcxManifestItem(manifestItems);
      if (ncxManifestItem) {
        const ncxPath = this.joinNormalizedPath(packageRoot, this.normalizeRelativeResourcePath(ncxManifestItem.href));
        items = this.parseNavigationFromNcxDocument(ncxPath, extractedRoot, spineIndexByHref);
      }
    }

    const dedupedItems = this.dedupeNavigationItems(items);
    if (dedupedItems.length > 0) {
      logger.info(TAG, `[NavParse] 解析到 ${dedupedItems.length} 个目录项`);
    }
    return dedupedItems;
  }

  public parseSpineFromOpf(extractedRoot: string): EBookChapter[] {
    try {
      const opfPath = this.resolveEpubPackageDocumentPath(extractedRoot);
      if (!opfPath || !this.pathExists(opfPath)) {
        logger.warn(TAG, `[SpineParse] OPF 文件未找到: extractedRoot=${extractedRoot}`);
        return [];
      }
      const opfText = this.readTextFileSync(opfPath);
      const packageRoot = this.getParentDir(opfPath);
      const manifestItems = this.parseOpfManifestItems(opfText);
      const spineIds = this.parseOpfSpineIds(opfText);

      if (spineIds.length === 0) {
        logger.warn(TAG, '[SpineParse] OPF spine 中无 itemref');
        return [];
      }

      const result: EBookChapter[] = [];
      for (let i = 0; i < spineIds.length; i++) {
        const idref = spineIds[i];
        const item = manifestItems.get(idref);
        if (!item) {
          continue;
        }
        const normalizedHref = this.normalizeRelativeResourcePath(item.href);
        const absolutePath = this.joinNormalizedPath(packageRoot, normalizedHref);
        const lowerHref = normalizedHref.toLowerCase();
        const isHtmlLike = lowerHref.endsWith('.html') || lowerHref.endsWith('.xhtml') ||
          lowerHref.endsWith('.htm') || lowerHref.endsWith('.svg');
        if (!isHtmlLike && !item.mediaType.includes('html') && !item.mediaType.includes('xml')) {
          continue;
        }
        const chapter: EBookChapter = {
          id: idref,
          bookId: '',
          chapterNumber: i + 1,
          title: `Chapter ${i + 1}`,
          content: '',
          startPosition: 0,
          endPosition: 0,
          wordCount: 0,
          resourceHref: normalizedHref,
          resourceFile: this.buildRelativePath(extractedRoot, absolutePath) || normalizedHref,
          resourceMediaType: item.mediaType,
          resourceLayoutType: 'TEXT_HTML',
          createTime: Date.now()
        };
        result.push(chapter);
      }

      const navigationItems = this.parseNavigationFromManifest(extractedRoot, packageRoot, manifestItems, result);
      const titleByResourcePath = new Map<string, string>();
      for (let index = 0; index < navigationItems.length; index++) {
        const item = navigationItems[index];
        if (!titleByResourcePath.has(item.resourcePath) && item.title.trim().length > 0) {
          titleByResourcePath.set(item.resourcePath, item.title.trim());
        }
      }
      for (let index = 0; index < result.length; index++) {
        const chapter = result[index];
        const resourcePath = this.normalizeRelativeResourcePath(chapter.resourceFile ?? chapter.resourceHref ?? '');
        if (resourcePath.length > 0 && titleByResourcePath.has(resourcePath)) {
          const title = titleByResourcePath.get(resourcePath);
          chapter.title = title ? title : chapter.title;
        }
      }

      logger.info(TAG, `[SpineParse] 直接解析 OPF 得到 ${result.length} 个 spine 项`);
      return result;
    } catch (e) {
      logger.warn(TAG, `[SpineParse] OPF 解析失败: ${String(e)}`);
      return [];
    }
  }

  private isGeneratedNavigationTitleCandidate(title: string, tagName: string, attrsText: string): boolean {
    const normalizedTitle = title.replace(/\s+/g, ' ').trim();
    if (normalizedTitle.length <= 1 || normalizedTitle.length > 90) {
      return false;
    }
    if (/^(注|注释|标记|标注|脚注|尾注|备注|参考|引用|notes?|footnotes?|endnotes?)\s*[:：]?\s*$/i.test(normalizedTitle)) {
      return false;
    }
    if (/^(目录|上一页|下一页|返回|back|next|previous|contents?)$/i.test(normalizedTitle)) {
      return false;
    }
    if (/^[0-9０-９]+$/.test(normalizedTitle)) {
      return false;
    }
    const lowerTag = tagName.toLowerCase();
    const attrs = attrsText.toLowerCase();
    if (/(footnote|endnote|annotation|note-body|noteref|fnref)/i.test(attrs)) {
      return false;
    }
    const strongTitlePattern: RegExp =
      /^(第\s*[0-9０-９零〇一二两三四五六七八九十百千万亿]+\s*[章回卷节集部篇].{0,80}|卷\s*[0-9０-９零〇一二两三四五六七八九十百千万亿]+.{0,80}|Chapter\s+[0-9IVXLCDM]+.{0,80}|Part\s+[0-9IVXLCDM]+.{0,80}|Book\s+[0-9IVXLCDM]+.{0,80}|序章|序言|前言|楔子|引子|尾声|后记|附录.{0,40})$/i;
    const numberedTitlePattern: RegExp = /^[0-9０-９零〇一二两三四五六七八九十百千万亿]+\s*[、.．]\s*\S.{0,60}$/i;
    if (lowerTag.startsWith('h')) {
      return true;
    }
    if (attrs.includes('chapter') || attrs.includes('title') || attrs.includes('heading') || attrs.includes('headline')) {
      return true;
    }
    if (strongTitlePattern.test(normalizedTitle)) {
      return true;
    }
    return numberedTitlePattern.test(normalizedTitle) && attrs.includes('chap');
  }

  private buildGeneratedNavigationFragment(spineIndex: number, localIndex: number): string {
    return `mnx_nav_${spineIndex + 1}_${localIndex + 1}`;
  }

  private scanGeneratedNavigationFromHtml(
    htmlText: string,
    resourcePath: string,
    spineIndex: number,
    playOrderStart: number
  ): GeneratedNavigationScanResult {
    const items: EpubNavigationItem[] = [];
    let rebuiltHtml = '';
    let cursor = 0;
    let changed = false;
    let localIndex = 0;
    let playOrder = playOrderStart;
    const seenTitles: Set<string> = new Set();
    const blockPattern = /<(h[1-6]|p|div)\b([^>]*)>((?:(?!<(?:h[1-6]|p|div)\b)[\s\S])*?)<\/\1>/gi;
    let match = blockPattern.exec(htmlText);
    while (match !== null) {
      const tagName = String(match[1] ?? '');
      const attrsText = String(match[2] ?? '');
      const innerHtml = String(match[3] ?? '');
      const title = this.stripXmlTags(innerHtml);
      if (this.isGeneratedNavigationTitleCandidate(title, tagName, attrsText)) {
        const titleKey = `${spineIndex}:${title}`;
        if (!seenTitles.has(titleKey)) {
          seenTitles.add(titleKey);
          let fragment = this.extractXmlAttribute(attrsText, 'id');
          let replacement = String(match[0] ?? '');
          if (fragment.length <= 0) {
            fragment = this.buildGeneratedNavigationFragment(spineIndex, localIndex);
            replacement = `<${tagName}${attrsText} id="${fragment}">${innerHtml}</${tagName}>`;
            changed = true;
          }
          rebuiltHtml += htmlText.substring(cursor, match.index);
          rebuiltHtml += replacement;
          cursor = match.index + String(match[0] ?? '').length;
          items.push({
            id: `generated_${spineIndex}_${localIndex}`,
            title: title,
            href: `${resourcePath}#${fragment}`,
            resourcePath: resourcePath,
            fragment: fragment,
            spineIndex: spineIndex,
            level: tagName.toLowerCase().startsWith('h') ? Math.max(0, Number(tagName.substring(1)) - 1) : 0,
            playOrder: playOrder
          });
          playOrder++;
          localIndex++;
        }
      }
      match = blockPattern.exec(htmlText);
    }

    if (changed) {
      rebuiltHtml += htmlText.substring(cursor);
    }
    return {
      items: items,
      htmlText: changed ? rebuiltHtml : htmlText,
      changed: changed
    };
  }

  public parseGeneratedNavigationFromSpine(
    extractedRoot: string,
    spineItems: EBookChapter[]
  ): EpubNavigationItem[] {
    const result: EpubNavigationItem[] = [];
    if (!extractedRoot || extractedRoot.trim().length <= 0 || spineItems.length <= 0) {
      return result;
    }
    let playOrder = 1;
    for (let spineIndex = 0; spineIndex < spineItems.length; spineIndex++) {
      const chapter = spineItems[spineIndex];
      const resourcePath = this.normalizeRelativeResourcePath(chapter.resourceFile ?? chapter.resourceHref ?? '');
      if (resourcePath.length <= 0) {
        continue;
      }
      const chapterPath = this.joinNormalizedPath(extractedRoot, resourcePath);
      if (!this.pathExists(chapterPath)) {
        continue;
      }
      try {
        const htmlText = this.readTextFileSync(chapterPath);
        const scanResult = this.scanGeneratedNavigationFromHtml(htmlText, resourcePath, spineIndex, playOrder);
        if (scanResult.items.length <= 0) {
          continue;
        }
        if (scanResult.changed) {
          this.writeTextFileSync(chapterPath, scanResult.htmlText);
        }
        for (let itemIndex = 0; itemIndex < scanResult.items.length; itemIndex++) {
          result.push(scanResult.items[itemIndex]);
        }
        playOrder += scanResult.items.length;
      } catch (error) {
        logger.warn(TAG, `[NavParse] 扫描正文目录失败: spine=${spineIndex}, path=${chapterPath}, error=${String(error)}`);
      }
    }
    const dedupedItems = this.dedupeNavigationItems(result);
    if (dedupedItems.length > 0) {
      logger.info(TAG, `[NavParse] 从正文标题生成 ${dedupedItems.length} 个目录项`);
    }
    return dedupedItems;
  }

  public parseNavigationFromOpf(
    extractedRoot: string,
    spineItems: EBookChapter[]
  ): EpubNavigationItem[] {
    try {
      if (!extractedRoot || extractedRoot.trim().length <= 0 || spineItems.length <= 0) {
        return [];
      }
      const opfPath = this.resolveEpubPackageDocumentPath(extractedRoot);
      if (!opfPath || !this.pathExists(opfPath)) {
        return [];
      }
      const opfText = this.readTextFileSync(opfPath);
      const packageRoot = this.getParentDir(opfPath);
      const manifestItems = this.parseOpfManifestItems(opfText);
      return this.parseNavigationFromManifest(extractedRoot, packageRoot, manifestItems, spineItems);
    } catch (error) {
      logger.warn(TAG, `[NavParse] OPF 目录解析失败: ${String(error)}`);
      return [];
    }
  }

  private async ensureEpubExtractionRoot(): Promise<string> {
    const extractionRoot = this.buildEpubExtractionPath();
    const containerPath = `${extractionRoot}/META-INF/container.xml`;
    if (this.pathExists(containerPath)) {
      return extractionRoot;
    }

    if (!this.pathExists(extractionRoot)) {
      SafeFileUtils.mkdirSync(extractionRoot, true);
    }
    await zlib.decompressFile(this.normalizeFsPath(this.filePath), extractionRoot);
    if (!this.pathExists(containerPath)) {
      throw new Error('EPUB 解压完成但缺少 META-INF/container.xml，文件可能已损坏');
    }
    return extractionRoot;
  }

  private buildEpubExtractionPath(): string {
    const normalizedPath = this.normalizeFsPath(this.filePath);
    const parentDir = this.getParentDir(normalizedPath);
    const baseName = this.getFileNameFromPath(normalizedPath).replace(/\.[^.]+$/i, '');
    const safeBaseName = baseName.replace(/[^0-9A-Za-z_\-\u4E00-\u9FFF]+/g, '_').replace(/_+/g, '_');
    const hash = Math.abs(this.hashString(normalizedPath)).toString(36);
    return `${parentDir}/.__epub_extract_${safeBaseName}_${hash}`;
  }

  private resolveEpubPackageDocumentPath(extractionRoot: string): string {
    const containerPath = `${extractionRoot}/META-INF/container.xml`;
    if (!this.pathExists(containerPath)) {
      return '';
    }
    const containerText = this.readTextFileSync(containerPath);
    const match = containerText.match(EPUB_CONTAINER_FULL_PATH_PATTERN);
    if (!match || !match[1]) {
      return '';
    }
    return this.joinNormalizedPath(extractionRoot, this.normalizeRelativeResourcePath(match[1]));
  }

  private enrichEpubChapterResource(
    chapter: ReaderKitChapter,
    packageRoot: string,
    extractionRoot: string
  ): ReaderKitChapter {
    const result: ReaderKitChapter = {
      id: chapter.id,
      title: chapter.title,
      content: chapter.content,
      resourceHref: chapter.resourceHref || '',
      resourceFile: chapter.resourceFile || '',
      resourceMediaType: chapter.resourceMediaType || '',
      resourceLayoutType: chapter.resourceLayoutType || 'UNKNOWN',
      resourceImagePath: chapter.resourceImagePath || '',
      resourceImageRelativePath: chapter.resourceImageRelativePath || ''
    };

    const rawResourcePath: string = result.resourceFile || result.resourceHref || '';
    if (rawResourcePath.length <= 0) {
      return result;
    }

    const normalizedResourcePath = this.normalizeRelativeResourcePath(rawResourcePath);
    const chapterResourcePath = this.resolveResourcePathWithFallback(packageRoot, extractionRoot, normalizedResourcePath);
    result.resourceFile = normalizedResourcePath;
    if ((result.resourceHref || '').length <= 0) {
      result.resourceHref = normalizedResourcePath;
    }
    result.resourceMediaType = this.inferMediaTypeFromPath(normalizedResourcePath);

    if (result.resourceMediaType.startsWith('image/')) {
      result.resourceLayoutType = 'IMAGE_PAGE';
      result.resourceImagePath = chapterResourcePath;
      result.resourceImageRelativePath = this.buildRelativePath(extractionRoot, chapterResourcePath);
      return result;
    }

    if (!this.pathExists(chapterResourcePath)) {
      return result;
    }

    const lowerPath = chapterResourcePath.toLowerCase();
    const isHtmlLike = lowerPath.endsWith('.html') || lowerPath.endsWith('.xhtml') || lowerPath.endsWith('.htm') || lowerPath.endsWith('.svg');
    if (!isHtmlLike) {
      return result;
    }

    const htmlText = this.readTextFileSync(chapterResourcePath);
    const firstImageRef = this.extractFirstLocalImageRef(htmlText);
    const textLength = this.measureHtmlTextLength(htmlText);
    if (firstImageRef.length <= 0) {
      result.resourceLayoutType = textLength <= 24 ? 'EMPTY_HTML' : 'TEXT_HTML';
      return result;
    }

    const imagePath = this.resolveResourcePathWithFallback(this.getParentDir(chapterResourcePath), extractionRoot, firstImageRef);
    if (!this.pathExists(imagePath)) {
      result.resourceLayoutType = textLength <= 80 ? 'IMAGE_PAGE' : 'MIXED_HTML';
      result.resourceImageRelativePath = this.normalizeRelativeResourcePath(firstImageRef);
      return result;
    }

    result.resourceLayoutType = textLength <= 80 ? 'IMAGE_PAGE' : 'MIXED_HTML';
    result.resourceImagePath = imagePath;
    result.resourceImageRelativePath = this.buildRelativePath(extractionRoot, imagePath);
    return result;
  }

  private resolveResourcePathWithFallback(baseDir: string, extractionRoot: string, relativePath: string): string {
    const normalized = this.normalizeRelativeResourcePath(relativePath);
    const primary = this.joinNormalizedPath(baseDir, normalized);
    if (this.pathExists(primary)) {
      return primary;
    }
    return this.joinNormalizedPath(extractionRoot, normalized);
  }

  private normalizeFsPath(path: string): string {
    if (path.startsWith('file://')) {
      const stripped = path.substring(7);
      return stripped.startsWith('/') ? stripped : `/${stripped}`;
    }
    return path;
  }

  private normalizeRelativeResourcePath(path: string): string {
    return path
      .trim()
      .replace(/\\/g, '/')
      .replace(/#.*/, '')
      .replace(/\?.*/, '')
      .replace(/\/+/g, '/')
      .replace(/^\.\//, '');
  }

  private joinNormalizedPath(baseDir: string, relativePath: string): string {
    if (relativePath.startsWith('/')) {
      return relativePath;
    }
    const baseParts = baseDir.replace(/\\/g, '/').split('/').filter((part: string) => part.length > 0);
    const relativeParts = relativePath.replace(/\\/g, '/').split('/');
    const resolved = [...baseParts];
    for (const part of relativeParts) {
      if (!part || part === '.') {
        continue;
      }
      if (part === '..') {
        if (resolved.length > 0) {
          resolved.pop();
        }
        continue;
      }
      resolved.push(part);
    }
    return `${baseDir.startsWith('/') ? '/' : ''}${resolved.join('/')}`;
  }

  private getParentDir(path: string): string {
    const normalized = path.replace(/\\/g, '/');
    const separatorIndex = normalized.lastIndexOf('/');
    if (separatorIndex <= 0) {
      return normalized.startsWith('/') ? '/' : '.';
    }
    return normalized.substring(0, separatorIndex);
  }

  private pathExists(path: string): boolean {
    try {
      SafeFileUtils.statSync(path);
      return true;
    } catch (_error) {
      return false;
    }
  }

  private readTextFileSync(path: string): string {
    const file = SafeFileUtils.openSync(path, fileIo.OpenMode.READ_ONLY);
    const stat = SafeFileUtils.statSync(file.fd);
    const buffer = new ArrayBuffer(stat.size);
    SafeFileUtils.readSync(file.fd, buffer);
    SafeFileUtils.closeSync(file);
    return new util.TextDecoder('utf-8', { ignoreBOM: true }).decodeToString(new Uint8Array(buffer));
  }

  private writeTextFileSync(path: string, content: string): void {
    const encoder = new util.TextEncoder();
    const encoded = encoder.encodeInto(content);
    const file = SafeFileUtils.openSync(path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      SafeFileUtils.writeSync(file.fd, encoded.buffer as ArrayBuffer);
    } finally {
      SafeFileUtils.closeSync(file);
    }
  }

  private extractFirstLocalImageRef(htmlText: string): string {
    EPUB_IMAGE_RESOURCE_PATTERN.lastIndex = 0;
    let match = EPUB_IMAGE_RESOURCE_PATTERN.exec(htmlText);
    while (match) {
      const candidate = String(match[1] || '').trim();
      if (candidate.length > 0 &&
        !candidate.startsWith('http://') &&
        !candidate.startsWith('https://') &&
        !candidate.startsWith('data:')) {
        return candidate;
      }
      match = EPUB_IMAGE_RESOURCE_PATTERN.exec(htmlText);
    }
    return '';
  }

  private measureHtmlTextLength(htmlText: string): number {
    const stripped = htmlText
      .replace(/<script[\s\S]*?<\/script>/ig, ' ')
      .replace(/<style[\s\S]*?<\/style>/ig, ' ')
      .replace(/<[^>]+>/g, ' ')
      .replace(/&nbsp;/ig, ' ')
      .replace(/\s+/g, ' ')
      .trim();
    return stripped.length;
  }

  private buildRelativePath(rootDir: string, fullPath: string): string {
    const normalizedRoot = rootDir.replace(/\\/g, '/').replace(/\/$/, '');
    const normalizedFullPath = fullPath.replace(/\\/g, '/');
    const prefix = `${normalizedRoot}/`;
    if (normalizedFullPath.startsWith(prefix)) {
      return normalizedFullPath.substring(prefix.length);
    }
    return normalizedFullPath;
  }

  private isFixedLayoutEpub(infoObj: Record<string, Object>, opfText: string): boolean {
    const renditionLayout = this.getStringProperty(infoObj, ['renditionLayout', 'layout']);
    if (renditionLayout.toLowerCase().includes('pre-paginated')) {
      return true;
    }
    return EPUB_FIXED_LAYOUT_PATTERN.test(opfText);
  }

  private inferMediaTypeFromPath(path: string): string {
    const lower = path.toLowerCase();
    if (lower.endsWith('.xhtml') || lower.endsWith('.html') || lower.endsWith('.htm')) {
      return 'application/xhtml+xml';
    }
    if (lower.endsWith('.svg')) {
      return 'image/svg+xml';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    if (lower.endsWith('.bmp')) {
      return 'image/bmp';
    }
    if (lower.endsWith('.avif')) {
      return 'image/avif';
    }
    return '';
  }

  private hashString(text: string): number {
    let hash = 0;
    for (let index = 0; index < text.length; index++) {
      hash = ((hash << 5) - hash) + text.charCodeAt(index);
      hash |= 0;
    }
    return hash;
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
    ebook.contentMode = bookInfo.contentMode || EBookContentMode.UNKNOWN;
    ebook.preferredReaderEngine = bookInfo.preferredReaderEngine || EBookReaderEngine.READER_KIT;
    ebook.extractedRootPath = bookInfo.extractedRootPath || '';
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
          resourceHref: ch.resourceHref || '',
          resourceFile: ch.resourceFile || '',
          resourceMediaType: ch.resourceMediaType || '',
          resourceLayoutType: ch.resourceLayoutType || '',
          resourceImagePath: ch.resourceImagePath || '',
          resourceImageRelativePath: ch.resourceImageRelativePath || '',
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
    ebook.contentMode = this.format === EBookFormat.TXT ? EBookContentMode.REFLOWABLE_TEXT : EBookContentMode.UNKNOWN;
    ebook.preferredReaderEngine = this.format === EBookFormat.TXT ? EBookReaderEngine.TEXT : EBookReaderEngine.READER_KIT;
    ebook.extractedRootPath = '';
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
  contentMode: EBookContentMode;
  preferredReaderEngine: EBookReaderEngine;
  extractedRootPath: string;
}

/**
 * Reader Kit 章节信息接口
 */
interface ReaderKitChapter {
  id: string;
  title: string;
  content: string;
  resourceHref?: string;
  resourceFile?: string;
  resourceMediaType?: string;
  resourceLayoutType?: string;
  resourceImagePath?: string;
  resourceImageRelativePath?: string;
}

interface ReaderKitContentAnalysis {
  chapters: ReaderKitChapter[];
  contentMode: EBookContentMode;
  preferredReaderEngine: EBookReaderEngine;
  extractedRootPath: string;
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

      let readerKitResult: EBookCoverExtractionResult | null = null;
      if (isReaderKitEnabled()) {
        readerKitResult = await EBookCoverExtractor.extractReaderKitCover(filePath, savePath);
        if (readerKitResult.success) {
          return readerKitResult;
        }
        logger.warn(EBookCoverExtractor.TAG, `ReaderKit 封面提取未成功，准备按格式降级: ${readerKitResult.errorMessage || '未知原因'}`);
      } else {
        logger.warn(EBookCoverExtractor.TAG, `Reader Kit temporarily disabled, skip ReaderKit cover extraction: ${filePath}`);
      }

      if (EBookCoverExtractor.isKindleFormat(filePath)) {
        return await EBookCoverExtractor.extractKindleCover(filePath, savePath);
      }

      if (readerKitResult) {
        return readerKitResult;
      }

      return {
        success: false,
        coverPath: '',
        candidateImages: [],
        errorMessage: 'Reader Kit is temporarily disabled'
      };

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      if (isReaderKitUnavailableError(errorMsg)) {
        logger.warn(EBookCoverExtractor.TAG, `Reader Kit unavailable, skip cover extraction: ${errorMsg}`);
      } else {
        logger.error(EBookCoverExtractor.TAG, `提取封面失败: ${errorMsg}`);
      }
      return {
        success: false,
        coverPath: '',
        candidateImages: [],
        errorMessage: errorMsg
      };
    }
  }

  private static async extractReaderKitCover(filePath: string, savePath: string): Promise<EBookCoverExtractionResult> {
    try {
      logger.info(EBookCoverExtractor.TAG, `使用 ReaderKit 提取电子书封面: ${filePath}`);
      const parserHandler: bookParser.BookParserHandler =
        await createReaderKitBookParserHandler(filePath, 'extractCover');
      if (!parserHandler) {
        logger.warn(EBookCoverExtractor.TAG, `Reader Kit handler unavailable, skip cover extraction: ${filePath}`);
        return {
          success: false,
          coverPath: '',
          candidateImages: [],
          errorMessage: 'Reader Kit handler unavailable'
        };
      }

      // 获取书籍信息
      const bookInfo: bookParser.BookInfo = parserHandler.getBookInfo();
      const coverImageRef = bookInfo.bookCoverImage ? bookInfo.bookCoverImage.trim() : '';

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

      if (EBookCoverExtractor.isDirectFilePath(coverImageRef)) {
        const directCoverData = EBookCoverExtractor.readFileAsArrayBuffer(coverImageRef);
        if (directCoverData && directCoverData.byteLength > 0) {
          logger.info(EBookCoverExtractor.TAG, `ReaderKit 返回封面文件路径，已读取数据: ${directCoverData.byteLength} 字节`);
          const directSavedPath = await EBookCoverExtractor.saveImageToFile(directCoverData, savePath, coverImageRef);
          if (directSavedPath) {
            logger.info(EBookCoverExtractor.TAG, `ReaderKit 封面文件保存成功: ${directSavedPath}`);
            return {
              success: true,
              coverPath: directSavedPath,
              candidateImages: [directSavedPath]
            };
          }
        }
      }

      const resourceResult = await EBookCoverExtractor.extractReaderKitCoverResource(parserHandler, coverImageRef, savePath);
      if (resourceResult.success) {
        return resourceResult;
      }

      logger.warn(EBookCoverExtractor.TAG, `无法通过 ReaderKit 提取封面图片: ${resourceResult.errorMessage || coverImageRef}`);

      // 如果直接提取失败，返回封面引用信息（供后续处理）
      return {
        success: false,
        coverPath: '',
        candidateImages: [],
        errorMessage: resourceResult.errorMessage || `封面引用: ${coverImageRef}，但无法提取`
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      if (isReaderKitUnavailableError(errorMsg)) {
        logger.warn(EBookCoverExtractor.TAG, `Reader Kit unavailable, skip cover extraction: ${errorMsg}`);
      } else {
        logger.error(EBookCoverExtractor.TAG, `提取封面失败: ${errorMsg}`);
      }
      return {
        success: false,
        coverPath: '',
        candidateImages: [],
        errorMessage: errorMsg
      };
    }
  }

  private static async extractReaderKitCoverResource(
    parserHandler: bookParser.BookParserHandler,
    coverImageRef: string,
    savePath: string
  ): Promise<EBookCoverExtractionResult> {
    const resourcePaths = EBookCoverExtractor.buildReaderKitCoverResourceCandidates(coverImageRef);
    if (resourcePaths.length <= 0) {
      return {
        success: false,
        coverPath: '',
        candidateImages: [],
        errorMessage: 'ReaderKit 封面资源路径为空'
      };
    }

    const spineIndices = EBookCoverExtractor.getReaderKitResourceSpineIndices(parserHandler);
    let lastError = '';
    for (let spinePos = 0; spinePos < spineIndices.length; spinePos++) {
      const spineIndex = spineIndices[spinePos];
      for (let pathPos = 0; pathPos < resourcePaths.length; pathPos++) {
        const resourcePath = resourcePaths[pathPos];
        try {
          logger.info(EBookCoverExtractor.TAG, `尝试 ReaderKit getResourceContent(${spineIndex}, "${resourcePath}") 提取封面...`);
          const resourceData = parserHandler.getResourceContent(spineIndex, resourcePath);
          if (!resourceData || resourceData.byteLength <= 0) {
            lastError = `ReaderKit getResourceContent 返回空数据: spine=${spineIndex}, path=${resourcePath}`;
            logger.warn(EBookCoverExtractor.TAG, lastError);
            continue;
          }

          logger.info(
            EBookCoverExtractor.TAG,
            `ReaderKit 获取封面数据成功: spine=${spineIndex}, path=${resourcePath}, size=${resourceData.byteLength}, header=${EBookCoverExtractor.getImageHeaderHex(resourceData, 12)}`
          );
          const savedPath = await EBookCoverExtractor.saveImageToFile(resourceData, savePath, resourcePath);
          if (savedPath) {
            logger.info(EBookCoverExtractor.TAG, `ReaderKit 封面图片保存成功: ${savedPath}`);
            return {
              success: true,
              coverPath: savedPath,
              candidateImages: [savedPath]
            };
          }
          lastError = `ReaderKit 封面数据无法保存: spine=${spineIndex}, path=${resourcePath}`;
        } catch (error) {
          lastError = `ReaderKit getResourceContent 失败: spine=${spineIndex}, path=${resourcePath}, error=${String(error)}`;
          logger.warn(EBookCoverExtractor.TAG, lastError);
        }
      }
    }

    return {
      success: false,
      coverPath: '',
      candidateImages: [],
      errorMessage: lastError || `ReaderKit 无法读取封面资源: ${coverImageRef}`
    };
  }

  private static isDirectFilePath(path: string): boolean {
    const trimmed = path.trim().toLowerCase();
    return trimmed.startsWith('file://') || trimmed.startsWith('/data/') || trimmed.startsWith('/storage/');
  }

  private static buildReaderKitCoverResourceCandidates(coverImageRef: string): string[] {
    const candidates: string[] = [];
    EBookCoverExtractor.appendUniqueString(candidates, coverImageRef.trim());

    const slashNormalized = coverImageRef.trim().replace(/\\/g, '/');
    EBookCoverExtractor.appendUniqueString(candidates, slashNormalized);

    let decoded = slashNormalized;
    try {
      decoded = decodeURIComponent(slashNormalized);
    } catch (_error) {
      decoded = slashNormalized;
    }
    EBookCoverExtractor.appendUniqueString(candidates, decoded);

    let noLeadingSlash = decoded;
    while (noLeadingSlash.startsWith('/')) {
      noLeadingSlash = noLeadingSlash.substring(1);
    }
    EBookCoverExtractor.appendUniqueString(candidates, noLeadingSlash);

    let noCurrentDir = noLeadingSlash;
    while (noCurrentDir.startsWith('./')) {
      noCurrentDir = noCurrentDir.substring(2);
    }
    EBookCoverExtractor.appendUniqueString(candidates, noCurrentDir);

    const lastSlash = noCurrentDir.lastIndexOf('/');
    if (lastSlash >= 0 && lastSlash + 1 < noCurrentDir.length) {
      EBookCoverExtractor.appendUniqueString(candidates, noCurrentDir.substring(lastSlash + 1));
    }

    return candidates;
  }

  private static appendUniqueString(values: string[], value: string): void {
    const trimmed = value.trim();
    if (trimmed.length > 0 && !values.includes(trimmed)) {
      values.push(trimmed);
    }
  }

  private static getReaderKitResourceSpineIndices(parserHandler: bookParser.BookParserHandler): number[] {
    const indices: number[] = [-1];
    try {
      const spineList: bookParser.SpineItem[] = parserHandler.getSpineList();
      for (let i = 0; i < spineList.length; i++) {
        const spineIndex = spineList[i].index;
        if (!indices.includes(spineIndex)) {
          indices.push(spineIndex);
        }
      }
    } catch (error) {
      logger.warn(EBookCoverExtractor.TAG, `读取 ReaderKit spine 列表失败，仅使用 -1 提取封面: ${String(error)}`);
    }
    return indices;
  }

  private static isKindleFormat(filePath: string): boolean {
    const normalizedPath = filePath.toLowerCase();
    return normalizedPath.endsWith('.mobi') ||
      normalizedPath.endsWith('.azw') ||
      normalizedPath.endsWith('.azw3') ||
      normalizedPath.includes('.mobi?') ||
      normalizedPath.includes('.azw?') ||
      normalizedPath.includes('.azw3?');
  }

  private static async extractKindleCover(filePath: string, savePath: string): Promise<EBookCoverExtractionResult> {
    try {
      logger.info(EBookCoverExtractor.TAG, `使用本地 Kindle 转换结果提取封面: ${filePath}`);
      const result = await convertMobiToExtractedDir(filePath);
      if (!result.success) {
        return {
          success: false,
          coverPath: '',
          candidateImages: [],
          errorMessage: result.errorMessage || 'Kindle 本地转换未提取到封面'
        };
      }

      const sourceCoverPath = result.coverImagePath.trim();
      if (sourceCoverPath.length <= 0) {
        return {
          success: false,
          coverPath: '',
          candidateImages: [],
          errorMessage: 'Kindle 文件没有本地封面图片'
        };
      }

      const imageData = EBookCoverExtractor.readFileAsArrayBuffer(sourceCoverPath);
      if (!imageData || imageData.byteLength <= 0) {
        return {
          success: false,
          coverPath: '',
          candidateImages: [],
          errorMessage: `Kindle 本地封面读取失败: ${sourceCoverPath}`
        };
      }

      const savedPath = await EBookCoverExtractor.saveImageToFile(imageData, savePath, sourceCoverPath);
      if (!savedPath) {
        return {
          success: false,
          coverPath: '',
          candidateImages: [],
          errorMessage: 'Kindle 本地封面保存失败'
        };
      }

      return {
        success: true,
        coverPath: savedPath,
        candidateImages: [savedPath]
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.warn(EBookCoverExtractor.TAG, `Kindle 本地封面提取失败: ${errorMsg}`);
      return {
        success: false,
        coverPath: '',
        candidateImages: [],
        errorMessage: errorMsg
      };
    }
  }

  private static readFileAsArrayBuffer(filePath: string): ArrayBuffer | null {
    try {
      const normalizedPath = filePath.startsWith('file://') ? filePath.substring(7) : filePath;
      const file = SafeFileUtils.openSync(normalizedPath, fileIo.OpenMode.READ_ONLY);
      try {
        const stat = SafeFileUtils.statSync(file.fd);
        const buffer = new ArrayBuffer(stat.size);
        const readLength = SafeFileUtils.readSync(file.fd, buffer);
        if (readLength !== stat.size) {
          logger.warn(EBookCoverExtractor.TAG, `读取封面长度不一致: expected=${stat.size}, actual=${readLength}`);
        }
        return buffer;
      } finally {
        SafeFileUtils.closeSync(file);
      }
    } catch (error) {
      logger.warn(EBookCoverExtractor.TAG, `读取封面文件失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 保存图片到文件
   */
  private static async saveImageToFile(imageData: ArrayBuffer, basePath: string, originalName: string): Promise<string | null> {
    try {
      // 确定文件扩展名
      const ext = EBookCoverExtractor.getImageExtension(originalName, imageData);
      const fileName = `cover_${Date.now()}.webp`;
      const fullPath = `${basePath}/${fileName}`;

      // 确保目录存在
      try {
        SafeFileUtils.mkdirSync(basePath, true);
      } catch (e) {
        // 目录可能已存在
      }

      // 优先标准化为 WebP；部分 MOBI 内嵌封面可能无法被 PixelMap 解码，失败时保留原图。
      const imageSource = image.createImageSource(imageData);
      let packedBuffer: ArrayBuffer = new ArrayBuffer(0);
      try {
        const pixelMap = await EBookCoverExtractor.createPixelMapForCover(imageSource, originalName);
        try {
          const imagePacker = image.createImagePacker();
          try {
            packedBuffer = await imagePacker.packToData(pixelMap, {
              format: 'image/webp',
              quality: 90
            });
          } finally {
            imagePacker.release();
          }
        } finally {
          pixelMap.release();
        }
      } finally {
        imageSource.release();
      }

      const file = SafeFileUtils.openSync(fullPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      try {
        SafeFileUtils.writeSync(file.fd, packedBuffer);
      } finally {
        SafeFileUtils.closeSync(file);
      }
      logger.info(EBookCoverExtractor.TAG, `封面图片已标准化保存为 WebP: ${fullPath}, packed=${packedBuffer.byteLength}, original=${originalName}, sourceExt=${ext}`);

      logger.info(EBookCoverExtractor.TAG, `图片保存成功: ${fullPath}, 大小: ${imageData.byteLength} 字节`);
      return fullPath;
    } catch (error) {
      const fallbackPath = EBookCoverExtractor.saveRawImageToFile(imageData, basePath, originalName);
      if (fallbackPath) {
        logger.warn(EBookCoverExtractor.TAG, `封面标准化失败，已原样保存: ${fallbackPath}, error=${String(error)}`);
        return fallbackPath;
      }
      logger.error(EBookCoverExtractor.TAG, `保存图片失败: ${String(error)}, original=${originalName}, header=${EBookCoverExtractor.getImageHeaderHex(imageData, 16)}`);
      return null;
    }
  }

  private static async createPixelMapForCover(imageSource: image.ImageSource, originalName: string): Promise<image.PixelMap> {
    try {
      return await imageSource.createPixelMap({
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
    } catch (error) {
      logger.warn(EBookCoverExtractor.TAG, `封面按 RGBA_8888 解码失败，改用默认解码: original=${originalName}, error=${String(error)}`);
      return await imageSource.createPixelMap();
    }
  }

  private static saveRawImageToFile(imageData: ArrayBuffer, basePath: string, originalName: string): string | null {
    const ext = EBookCoverExtractor.detectImageExtensionFromData(imageData);
    if (ext.length <= 0) {
      logger.warn(EBookCoverExtractor.TAG, `封面原图格式无法识别，不能原样保存: original=${originalName}, header=${EBookCoverExtractor.getImageHeaderHex(imageData, 16)}`);
      return null;
    }

    try {
      try {
        SafeFileUtils.mkdirSync(basePath, true);
      } catch (e) {
        // 目录可能已存在
      }

      const fileName = `cover_${Date.now()}_raw${ext}`;
      const fullPath = `${basePath}/${fileName}`;
      const file = SafeFileUtils.openSync(fullPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        SafeFileUtils.writeSync(file.fd, imageData);
      } finally {
        SafeFileUtils.closeSync(file);
      }
      logger.info(EBookCoverExtractor.TAG, `封面原图保存成功: ${fullPath}, size=${imageData.byteLength}, original=${originalName}`);
      return fullPath;
    } catch (error) {
      logger.error(EBookCoverExtractor.TAG, `封面原图保存失败: ${String(error)}, original=${originalName}`);
      return null;
    }
  }

  /**
   * 获取图片扩展名
   */
  private static getImageExtension(originalName: string, imageData: ArrayBuffer): string {
    const detectedExt = EBookCoverExtractor.detectImageExtensionFromData(imageData);
    if (detectedExt.length > 0) {
      return detectedExt;
    }

    // 从原始文件名获取扩展名
    const match = originalName.match(/\.(jpg|jpeg|png|gif|webp|bmp)$/i);
    if (match) {
      return `.${match[1].toLowerCase()}`;
    }

    return '.jpg'; // 默认使用 jpg
  }

  private static detectImageExtensionFromData(imageData: ArrayBuffer): string {
    // 通过文件头检测图片格式
    const bytes = new Uint8Array(imageData);
    if (bytes[0] === 0xFF && bytes[1] === 0xD8) {
      return '.jpg';
    } else if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) {
      return '.png';
    } else if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) {
      return '.gif';
    } else if (bytes.length >= 12 &&
      bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
      bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
      return '.webp';
    } else if (bytes[0] === 0x42 && bytes[1] === 0x4D) {
      return '.bmp';
    }

    return '';
  }

  private static getImageHeaderHex(imageData: ArrayBuffer, maxBytes: number): string {
    const bytes = new Uint8Array(imageData);
    const length = Math.min(Math.max(maxBytes, 0), bytes.length);
    const parts: string[] = [];
    for (let i = 0; i < length; i++) {
      parts.push(bytes[i].toString(16).padStart(2, '0'));
    }
    return parts.join(' ');
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
        SafeFileUtils.mkdirSync(outputDir, true);
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
          SafeFileUtils.unlinkSync(savePath);
        } catch (unlinkError) {
          // 文件不存在，忽略
        }
        
        // 异步写入文件
        const file = SafeFileUtils.openSync(savePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
        await fileIo.write(file.fd, imgBuffer);
        SafeFileUtils.closeSync(file.fd);
        
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
 * MOBI/AZW/AZW3 解析器
 * 将 Kindle 系文件转换为伪 EPUB 目录结构，然后用 WebView 引擎渲染
 */
class MobiEBookParser extends EBookParser {
  constructor(filePath: string, format: EBookFormat) {
    super(filePath, format);
  }

  public static isSupportedFormat(format: EBookFormat): boolean {
    return format === EBookFormat.MOBI || format === EBookFormat.AZW || format === EBookFormat.AZW3;
  }

  public async parse(): Promise<EBook> {
    try {
      logger.info(TAG, `开始 ${this.format} 解析: ${this.filePath}`);
      const result = await convertMobiToExtractedDir(this.filePath);

      if (!result.success) {
        logger.warn(TAG, `${this.format} 转换失败，保留为 WebView 懒转换记录: ${result.errorMessage}`);
        return this.buildWebViewFallbackEBook(result.errorMessage || 'Kindle 本地转换失败');
      }

      // Build spine from the extracted OPF
      const spineChapters = EBookParserFactory.parseEpubSpineItems(result.extractedRootPath);
      if (spineChapters.length <= 0) {
        logger.warn(TAG, `${this.format} 转换后未解析到 spine，保留为 WebView 懒转换记录`);
        return this.buildWebViewFallbackEBook('Kindle 转换后未解析到 spine');
      }

      const metadata: EBookMetadata = {
        title: result.title || this.extractTitleFromFileName(this.getFileNameFromPath(this.filePath)),
        author: result.author || '未知作者',
        publisher: '',
        publishDate: '',
        isbn: '',
        language: 'zh-CN',
        description: `${this.format} 电子书`,
        coverImagePath: result.coverImagePath,
        tags: [],
        rating: 0
      };

      const ebook = this.generateDefaultEBook(this.filePath, this.format, metadata);
      ebook.fileSize = this.getFileSizeSafely();
      ebook.chapters = spineChapters;
      ebook.extractedRootPath = result.extractedRootPath;
      ebook.contentMode = EBookContentMode.REFLOWABLE_TEXT;
      ebook.preferredReaderEngine = EBookReaderEngine.WEBVIEW;

      logger.info(TAG, `${this.format} 解析完成: "${result.title}", ${spineChapters.length} 章`);
      return ebook;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error(TAG, `${this.format} MobiEBookParser 失败，保留为 WebView 懒转换记录: ${msg}`);
      return this.buildWebViewFallbackEBook(msg);
    }
  }

  private getFileSizeSafely(): number {
    try {
      const openTarget = this.filePath.startsWith('file://') ? this.filePath.substring(7) : this.filePath;
      const fileHandle = SafeFileUtils.openSync(openTarget, fileIo.OpenMode.READ_ONLY);
      const fileSize = SafeFileUtils.statSync(fileHandle.fd).size;
      SafeFileUtils.closeSync(fileHandle);
      return fileSize;
    } catch (error) {
      logger.warn(TAG, `${this.format} 获取文件大小失败: ${String(error)}`);
      return 0;
    }
  }

  private buildWebViewFallbackEBook(reason: string): EBook {
    const fileName = this.getFileNameFromPath(this.filePath);
    const now = Date.now();
    const metadata: EBookMetadata = {
      title: this.extractTitleFromFileName(fileName),
      author: '未知作者',
      publisher: '',
      publishDate: '',
      isbn: '',
      language: 'zh-CN',
      description: `${this.format} 电子书`,
      coverImagePath: '',
      tags: [this.format],
      rating: 0
    };
    const ebook = this.generateDefaultEBook(this.filePath, this.format, metadata);
    ebook.fileSize = this.getFileSizeSafely();
    ebook.contentMode = EBookContentMode.REFLOWABLE_TEXT;
    ebook.preferredReaderEngine = EBookReaderEngine.WEBVIEW;
    ebook.extractedRootPath = '';
    ebook.chapters = [{
      id: `kindle_lazy_${now}`,
      bookId: ebook.id,
      chapterNumber: 1,
      title: '开始阅读',
      content: reason.length > 0 ? `Kindle 本地转换将在阅读器中重试：${reason}` : 'Kindle 本地转换将在阅读器中重试',
      startPosition: 0,
      endPosition: 0,
      wordCount: 0,
      resourceHref: '',
      resourceFile: '',
      resourceMediaType: '',
      resourceLayoutType: '',
      resourceImagePath: '',
      resourceImageRelativePath: '',
      createTime: now
    }];
    return ebook;
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
   * - MOBI/AZW/AZW3: 优先使用 MobiEBookParser 转换为伪 EPUB 目录，WebView 引擎渲染
   * - Kindle 系本地转换失败时保留 WebView 懒转换记录，Reader Kit 只作为用户显式兜底入口
   * - EPUB: 使用 Reader Kit（官方 API）
   * - PDF: 使用 Web 组件预览方案
   * - TXT: 使用文件读取 + 自定义解析
   */
  public static createParser(filePath: string): EBookParser | null {
    const format = EBookParserFactory.detectFormat(filePath);

    if (!format) {
      logger.warn(TAG, `无法识别的电子书格式: ${filePath}`);
      return null;
    }

    // MOBI/AZW/AZW3: use MobiEBookParser for WebView-based rendering first
    if (MobiEBookParser.isSupportedFormat(format)) {
      logger.info(TAG, `使用 MobiEBookParser: ${format}`);
      return new MobiEBookParser(filePath, format);
    }

    // 优先使用 Reader Kit 解析支持的格式（除了 TXT，TXT 我们有自定义实现）
    if (ReaderKitEBookParser.isSupportedFormat(format) && format !== EBookFormat.TXT && format !== EBookFormat.MD) {
      if (isReaderKitEnabled()) {
        logger.info(TAG, `使用 Reader Kit 解析: ${format}`);
      } else {
        logger.warn(TAG, `Reader Kit disabled, use ReaderKit parser fallback: ${format}`);
      }
      return new ReaderKitEBookParser(filePath, format);
    }

    // 其他格式使用自定义解析器
    switch (format) {
      case EBookFormat.TXT:
      case EBookFormat.MD:
        return new TxtParser(filePath, format);
      case EBookFormat.PDF:
        return new PdfParser(filePath);
      default:
        logger.warn(TAG, `暂不支持的电子书格式: ${filePath}`);
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
      case 'md':
        return EBookFormat.MD;
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

  /**
   * 对 EPUB 文件执行懒解压（不触发完整解析），返回解压根路径
   * 供阅读器在 extractedRootPath 为空时按需调用
   */
  public static async ensureEpubExtracted(filePath: string): Promise<string> {
    if (!filePath || !filePath.toLowerCase().endsWith('.epub')) {
      return '';
    }
    const parser = new ReaderKitEBookParser(filePath, EBookFormat.EPUB);
    return parser.getExtractionRoot();
  }

  /**
   * 直接解析已解压 EPUB 的 OPF 文件，返回 spine 章节列表
   * 供阅读器在 Reader Kit catalog 章节缺少资源路径时作为兜底
   */
  public static parseEpubSpineItems(extractedRoot: string): EBookChapter[] {
    if (!extractedRoot || extractedRoot.trim().length === 0) {
      return [];
    }
    const parser = new ReaderKitEBookParser('', EBookFormat.EPUB);
    return parser.parseSpineFromOpf(extractedRoot);
  }

  /**
   * 直接解析已解压 EPUB 的目录结构（nav.xhtml / toc.ncx）
   * 返回已经映射到 spine 索引的目录项
   */
  public static parseEpubNavigationItems(
    extractedRoot: string,
    spineItems: EBookChapter[]
  ): EpubNavigationItem[] {
    if (!extractedRoot || extractedRoot.trim().length === 0 || spineItems.length <= 0) {
      return [];
    }
    const parser = new ReaderKitEBookParser('', EBookFormat.EPUB);
    return parser.parseNavigationFromOpf(extractedRoot, spineItems);
  }

  /**
   * 当 EPUB/MOBI 没有可靠 nav/ncx 时，从正文标题生成可跳转目录。
   */
  public static parseEpubGeneratedNavigationItems(
    extractedRoot: string,
    spineItems: EBookChapter[]
  ): EpubNavigationItem[] {
    if (!extractedRoot || extractedRoot.trim().length === 0 || spineItems.length <= 0) {
      return [];
    }
    const parser = new ReaderKitEBookParser('', EBookFormat.EPUB);
    return parser.parseGeneratedNavigationFromSpine(extractedRoot, spineItems);
  }
}

async function createReaderKitBookParserHandler(filePath: string, trigger: string): Promise<bookParser.BookParserHandler> {
  if (!isReaderKitEnabled()) {
    throw new Error('Reader Kit is unavailable in current environment');
  }

  logger.info(TAG, `[ReaderKit] 静态导入调用 getDefaultHandler: trigger=${trigger}`);
  return await bookParser.getDefaultHandler(filePath);
}

/**
 * TXT解析器实现
 */
class TxtParser extends EBookParser {
  private encoding: string = 'utf-8';

  constructor(filePath: string, format: EBookFormat = EBookFormat.TXT) {
    super(filePath, format);
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
      const ebook = this.generateDefaultEBook(this.filePath, this.format, extractionResult.metadata);
      ebook.fileSize = fileSize;
      ebook.contentMode = EBookContentMode.REFLOWABLE_TEXT;
      ebook.preferredReaderEngine = this.format === EBookFormat.MD ? EBookReaderEngine.MARKDOWN : EBookReaderEngine.TEXT;

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

      let file = SafeFileUtils.openSync(openTarget, fileIo.OpenMode.READ_ONLY);
      let stat = SafeFileUtils.statSync(file.fd);
      let buffer = new ArrayBuffer(stat.size);
      let readLen = SafeFileUtils.readSync(file.fd, buffer);
      SafeFileUtils.closeSync(file);

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
          const file = SafeFileUtils.openSync(candidate, fileIo.OpenMode.READ_ONLY);
          const stat = SafeFileUtils.statSync(file.fd);
          const buffer = new ArrayBuffer(stat.size);
          const readLen = SafeFileUtils.readSync(file.fd, buffer);
          SafeFileUtils.closeSync(file);

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

      let file = SafeFileUtils.openSync(openTarget, fileIo.OpenMode.READ_ONLY);
      let stat = SafeFileUtils.statSync(file.fd);
      SafeFileUtils.closeSync(file);
      return stat.size;
    } catch (firstError) {
      try {
        if (this.filePath.startsWith('file://')) {
          const stripped = this.filePath.substring(7);
          const candidate = stripped.startsWith('/') ? stripped : `/${stripped}`;
          const file = SafeFileUtils.openSync(candidate, fileIo.OpenMode.READ_ONLY);
          const stat = SafeFileUtils.statSync(file.fd);
          SafeFileUtils.closeSync(file);
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
 * 注意：EPUB 仍优先由 ReaderKitEBookParser 处理；
 * MOBI、AZW、AZW3 优先走本地伪 EPUB 转换；失败后保留 WebView 懒转换记录，
 * ReaderKit 只通过阅读器里的显式兜底按钮进入。
 * 
 * Reader Kit 支持的格式：
 * - EPUB: 使用 Reader Kit 解析
 * - MOBI/AZW/AZW3: 优先本地转换为 WebView 可读目录
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
        const stat = SafeFileUtils.statSync(this.filePath);
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
