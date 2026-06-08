import { SafeFileUtils } from '../../Utils/SafeFileUtils';
// 文件路径: entry/src/main/ets/Framework/Parsers/PdfToMangaImporter.ets
/**
 * PDF转漫画导入器
 * 将PDF文件的每一页转换为图片，并以漫画数据结构存储
 * 支持将PDF归类为"漫画"或"电子书"
 */

import { pdfService } from '@kit.PDFKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { logger } from '../../Utils/Logger';
import { generateUUID } from '../Utils/UUIDGenerator';
import { ComicInfoParser, ComicInfo } from '../../Utils/ComicInfoParser';

const TAG = 'PdfToMangaImporter';

/**
 * 延时函数，用于在转换页面之间让出主线程
 * 使用较长的延时确保UI有足够时间响应
 */
function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

const UI_YIELD_EVERY_PAGES = 4;
const UI_YIELD_DELAY_MS = 24;
const DOCUMENT_SESSION_PAGE_LIMIT = 24;
const LOW_MEMORY_DOCUMENT_SESSION_PAGE_LIMIT = 8;
const CRITICAL_MEMORY_DOCUMENT_SESSION_PAGE_LIMIT = 4;
const DOCUMENT_RECYCLE_DELAY_MS = 60;
const MEMORY_WARNING_LEVEL_KEY = 'systemMemoryWarningLevel';
const MEMORY_WARNING_TIME_KEY = 'systemMemoryWarningTime';

/**
 * PDF内容类型枚举
 */
export enum PdfContentType {
  MANGA = 'manga',     // 漫画类PDF
  EBOOK = 'ebook'      // 电子书类PDF
}

/**
 * PDF导入模式枚举
 */
export enum PdfImportMode {
  /** 单行本模式：整个PDF作为一部完整的漫画 */
  TANKOUBON = 'tankoubon',
  /** 单章节模式：PDF作为某部漫画的一个章节 */
  SINGLE_CHAPTER = 'single_chapter'
}

/**
 * PDF导入配置接口
 */
export interface PdfImportConfig {
  /** PDF文件路径 */
  pdfPath: string;
  /** 输出目录（图片存储位置） */
  outputDir: string;
  /** 内容类型（漫画/电子书） */
  contentType: PdfContentType;
  /** 导入模式（单行本/单章节） */
  importMode?: PdfImportMode;
  /** 漫画/电子书标题（可选，默认从PDF元数据或文件名提取） */
  title?: string;
  /** 作者（可选） */
  author?: string;
  /** 描述（可选） */
  description?: string;
  /** 章节编号（单章节模式） */
  chapterNumber?: number;
  /** 章节标题（单章节模式） */
  chapterTitle?: string;
  /** 已存在的漫画ID（单章节模式，合并到已有漫画时使用） */
  existingMangaId?: string;
}

/**
 * PDF导入结果接口
 */
export interface PdfImportResult {
  /** 是否成功 */
  success: boolean;
  /** 错误信息 */
  errorMessage?: string;
  /** 生成的漫画ID */
  mangaId?: string;
  /** 生成的章节ID */
  chapterId?: string;
  /** 漫画信息（用于数据库存储） */
  comicInfo?: PdfComicInfo;
  /** 图片文件列表 */
  imageFiles?: PdfPageImage[];
  /** 总页数 */
  totalPages?: number;
  /** 内容类型 */
  contentType?: PdfContentType;
  /** 导入模式 */
  importMode?: PdfImportMode;
  /** 封面路径 */
  coverPath?: string;
  /** 是否为新建漫画（单章节模式） */
  isNewManga?: boolean;
  /** 章节编号（单章节模式） */
  chapterNumber?: number;
  /** 章节标题（单章节模式） */
  chapterTitle?: string;
  /** 导入流程观测会话ID */
  originImportId?: string;
}

/**
 * PDF漫画信息接口（扩展自ComicInfo）
 */
export interface PdfComicInfo extends ComicInfo {
  /** 内部漫画ID */
  _mangaId?: string;
  /** 内部章节ID */
  _chapterId?: string;
  /** 内容类型 */
  _contentType?: PdfContentType;
  /** 标签列表 */
  tags?: string[];
}

/**
 * PDF页面图片信息接口
 */
export interface PdfPageImage {
  /** 页码（从0开始） */
  pageIndex: number;
  /** 图片文件路径 */
  imagePath: string;
  /** 图片宽度 */
  width?: number;
  /** 图片高度 */
  height?: number;
  /** 文件大小 */
  fileSize?: number;
}

/**
 * PDF导入进度回调
 */
export type PdfImportProgressCallback = (current: number, total: number, message: string) => void;

/**
 * PDF转漫画导入器类
 */
export class PdfToMangaImporter {
  private pdfDocument: pdfService.PdfDocument | null = null;
  private config: PdfImportConfig;
  private progressCallback?: PdfImportProgressCallback;
  private documentSessionPageLimit: number = DOCUMENT_SESSION_PAGE_LIMIT;
  private lastObservedMemoryWarningTime: number = 0;

  constructor(config: PdfImportConfig, progressCallback?: PdfImportProgressCallback) {
    this.config = config;
    this.progressCallback = progressCallback;
    this.lastObservedMemoryWarningTime = AppStorage.get<number>(MEMORY_WARNING_TIME_KEY) ?? 0;
  }

  private openPdfDocumentSession(reason: string): pdfService.ParseResult {
    if (!this.pdfDocument) {
      this.pdfDocument = new pdfService.PdfDocument();
    }
    const loadResult = this.pdfDocument.loadDocument(this.config.pdfPath);
    logger.info(TAG, `PDF 文档会话已打开: reason=${reason}, result=${loadResult}`);
    return loadResult;
  }

  private releasePdfDocument(reason: string): void {
    if (!this.pdfDocument) {
      return;
    }
    try {
      this.pdfDocument.releaseDocument();
      logger.info(TAG, `PDF 文档会话已释放: reason=${reason}`);
    } catch (error) {
      logger.warn(TAG, `释放 PDF 文档失败: reason=${reason}, error=${String(error)}`);
    } finally {
      this.pdfDocument = null;
    }
  }

  private async recyclePdfDocument(reason: string, delayMs: number = DOCUMENT_RECYCLE_DELAY_MS): Promise<void> {
    this.releasePdfDocument(reason);
    if (delayMs > 0) {
      await delay(delayMs);
    }
    const loadResult = this.openPdfDocumentSession(`reopen_${reason}`);
    if (loadResult !== pdfService.ParseResult.PARSE_SUCCESS) {
      throw new Error(`PDF 文档重建失败: ${loadResult}`);
    }
  }

  private consumePendingMemoryWarningLevel(): number {
    const warningTime = AppStorage.get<number>(MEMORY_WARNING_TIME_KEY) ?? 0;
    if (warningTime <= this.lastObservedMemoryWarningTime) {
      return -1;
    }
    this.lastObservedMemoryWarningTime = warningTime;
    return AppStorage.get<number>(MEMORY_WARNING_LEVEL_KEY) ?? -1;
  }

  private tightenDocumentSessionLimit(level: number): void {
    if (level >= 2) {
      this.documentSessionPageLimit = Math.min(this.documentSessionPageLimit, CRITICAL_MEMORY_DOCUMENT_SESSION_PAGE_LIMIT);
      return;
    }
    if (level >= 1) {
      this.documentSessionPageLimit = Math.min(this.documentSessionPageLimit, LOW_MEMORY_DOCUMENT_SESSION_PAGE_LIMIT);
      return;
    }
    if (level >= 0) {
      this.documentSessionPageLimit = Math.min(this.documentSessionPageLimit, Math.max(LOW_MEMORY_DOCUMENT_SESSION_PAGE_LIMIT, DOCUMENT_SESSION_PAGE_LIMIT / 2));
    }
  }

  private async yieldToUi(delayMs: number = UI_YIELD_DELAY_MS): Promise<void> {
    await delay(delayMs);
  }

  private buildPageImagePath(outputDir: string, pageIndex: number): string {
    return `${outputDir}/page_${String(pageIndex).padStart(4, '0')}.webp`;
  }

  /**
   * 执行PDF导入
   */
  public async import(): Promise<PdfImportResult> {
    try {
      const importMode = this.config.importMode || PdfImportMode.TANKOUBON;
      const isSingleChapter = importMode === PdfImportMode.SINGLE_CHAPTER;
      
      logger.info(TAG, `开始导入PDF: ${this.config.pdfPath}, 模式: ${importMode}`);
      this.reportProgress(0, 100, '正在加载PDF文档...');

      // 1. 加载PDF文档
      const loadResult = await this.loadPdfDocument();
      if (!loadResult.success) {
        return loadResult;
      }

      // 2. 获取PDF元数据
      const metadata = this.extractPdfMetadata();
      this.reportProgress(5, 100, '正在提取PDF元数据...');

      // 3. 创建输出目录结构
      // 单章节模式：使用已存在的漫画ID或生成新ID
      const mangaId = isSingleChapter && this.config.existingMangaId 
        ? this.config.existingMangaId 
        : generateUUID();
      const chapterId = generateUUID();
      const isNewManga = !this.config.existingMangaId;
      
      const chapterDir = await this.createOutputDirectories(mangaId, chapterId);
      this.reportProgress(10, 100, '正在创建目录结构...');

      // 4. 转换所有页面为图片
      // 为了避免长时间阻塞和原生缓存持续累积，转换过程中会周期性让出 UI，
      // 并按会话页数分段重建 PDF 文档。
      const pageCount = this.pdfDocument!.getPageCount();
      const imageFiles: PdfPageImage[] = [];
      
      logger.info(
        TAG,
        `开始转换 ${pageCount} 页 PDF，当前文档会话页数上限=${this.documentSessionPageLimit}，将分段重建文档以控制内存占用`
      );

      let pagesProcessedInCurrentSession = 0;
      for (let i = 0; i < pageCount; i++) {
        this.reportProgress(
          10 + Math.floor((i / pageCount) * 80),
          100,
          `正在转换第 ${i + 1}/${pageCount} 页（请耐心等待）...`
        );

        const pageImage = await this.convertPageToImage(i, chapterDir);
        if (pageImage) {
          imageFiles.push(pageImage);
        } else {
          logger.warn(TAG, `页面 ${i} 转换失败，跳过`);
        }

        pagesProcessedInCurrentSession++;
        if (i < pageCount - 1) {
          const memoryWarningLevel = this.consumePendingMemoryWarningLevel();
          if (memoryWarningLevel >= 0) {
            this.tightenDocumentSessionLimit(memoryWarningLevel);
            logger.warn(
              TAG,
              `检测到新的系统内存警告(level=${memoryWarningLevel})，立即重建 PDF 文档，会话页数上限收紧为 ${this.documentSessionPageLimit}`
            );
            await this.recyclePdfDocument(`memory_warning_level_${memoryWarningLevel}_after_page_${i + 1}`);
            pagesProcessedInCurrentSession = 0;
            continue;
          }

          if (pagesProcessedInCurrentSession >= this.documentSessionPageLimit) {
            logger.info(
              TAG,
              `已处理 ${i + 1}/${pageCount} 页，重建 PDF 文档以释放原生缓存（sessionLimit=${this.documentSessionPageLimit})`
            );
            await this.recyclePdfDocument(`session_limit_after_page_${i + 1}`);
            pagesProcessedInCurrentSession = 0;
            continue;
          }

          if ((i + 1) % UI_YIELD_EVERY_PAGES === 0) {
            await this.yieldToUi();
          }
        }
      }

      if (imageFiles.length === 0) {
        return {
          success: false,
          errorMessage: 'PDF转换失败：没有成功转换任何页面'
        };
      }

      this.reportProgress(90, 100, '正在生成元数据文件...');

      // 5. 生成ComicInfo.xml元数据文件
      const comicInfo = this.buildComicInfo(metadata, imageFiles.length, mangaId, chapterId);
      await this.writeComicInfoXml(chapterDir, comicInfo);

      // 6. 生成封面（使用第一页）- 仅新建漫画或单行本模式需要封面
      let coverPath: string | null = null;
      if (!isSingleChapter || isNewManga) {
        coverPath = await this.generateCover(mangaId, chapterDir, imageFiles);
      }

      this.reportProgress(100, 100, '导入完成');

      const chapterNumber = this.config.chapterNumber || 1;
      const chapterTitle = this.config.chapterTitle || `第${chapterNumber}话`;

      logger.info(TAG, `PDF导入成功: ${comicInfo.title}, 共 ${imageFiles.length} 页, 模式: ${importMode}`);

      return {
        success: true,
        mangaId: mangaId,
        chapterId: chapterId,
        comicInfo: comicInfo,
        imageFiles: imageFiles,
        totalPages: imageFiles.length,
        contentType: this.config.contentType,
        importMode: importMode,
        coverPath: coverPath || undefined,
        isNewManga: isNewManga,
        chapterNumber: isSingleChapter ? chapterNumber : undefined,
        chapterTitle: isSingleChapter ? chapterTitle : undefined
      };

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `PDF导入失败: ${errorMsg}`);
      return {
        success: false,
        errorMessage: errorMsg
      };
    } finally {
      // 清理资源
      this.releasePdfDocument('import_finished');
    }
  }

  /**
   * 加载PDF文档
   */
  private async loadPdfDocument(): Promise<PdfImportResult> {
    try {
      const loadResult = this.openPdfDocumentSession('initial_load');

      if (loadResult !== pdfService.ParseResult.PARSE_SUCCESS) {
        return {
          success: false,
          errorMessage: `PDF加载失败，错误码: ${loadResult}`
        };
      }

      const pdfDocument = this.pdfDocument;
      if (!pdfDocument) {
        return {
          success: false,
          errorMessage: 'PDF加载失败：文档实例为空'
        };
      }

      const pageCount = pdfDocument.getPageCount();
      if (pageCount <= 0) {
        return {
          success: false,
          errorMessage: 'PDF文件没有页面'
        };
      }

      logger.info(TAG, `PDF加载成功，共 ${pageCount} 页`);
      return { success: true };

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      return {
        success: false,
        errorMessage: `PDF加载异常: ${errorMsg}`
      };
    }
  }

  /**
   * 提取PDF元数据
   */
  private extractPdfMetadata(): PdfMetadata {
    const fileName = this.getFileNameFromPath(this.config.pdfPath);
    const title = this.config.title || this.extractTitleFromFileName(fileName);
    const author = this.config.author || '未知作者';
    const description = this.config.description || '';

    // 尝试从PDF获取页面尺寸信息
    let pageWidth = 0;
    let pageHeight = 0;
    if (this.pdfDocument) {
      try {
        const firstPage = this.pdfDocument.getPage(0);
        pageWidth = firstPage.getWidth();
        pageHeight = firstPage.getHeight();
      } catch (e) {
        logger.warn(TAG, `获取页面尺寸失败: ${e}`);
      }
    }

    return {
      title,
      author,
      description,
      pageCount: this.pdfDocument?.getPageCount() || 0,
      pageWidth,
      pageHeight
    };
  }

  /**
   * 创建输出目录结构
   * 结构: outputDir/manga_id/chapter_id/
   */
  private async createOutputDirectories(mangaId: string, chapterId: string): Promise<string> {
    const mangaDir = `${this.config.outputDir}/${mangaId}`;
    const chapterDir = `${mangaDir}/${chapterId}`;

    try {
      // 创建漫画目录
      try {
        SafeFileUtils.mkdirSync(mangaDir, true);
      } catch (e) {
        // 目录可能已存在
      }

      // 创建章节目录
      try {
        SafeFileUtils.mkdirSync(chapterDir, true);
      } catch (e) {
        // 目录可能已存在
      }

      logger.info(TAG, `创建目录结构: ${chapterDir}`);
      return chapterDir;

    } catch (error) {
      throw new Error(`创建目录失败: ${error}`);
    }
  }

  /**
   * 将 PixelMap 直接打包写入文件，避免先创建整块 ArrayBuffer 再复制到文件，降低峰值内存占用。
   */
  private async writePixelMapToFile(
    pixelMap: image.PixelMap,
    outputPath: string,
    format: string = 'image/jpeg',
    quality: number = 90
  ): Promise<void> {
    const packOpts: image.PackingOption = {
      format: format,
      quality: quality
    };
    const imagePackerApi = image.createImagePacker();
    const file = SafeFileUtils.openSync(
      outputPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    try {
      await imagePackerApi.packToFile(pixelMap, file.fd, packOpts);
    } finally {
      try {
        SafeFileUtils.closeSync(file);
      } catch (closeError) {
        logger.warn(TAG, `关闭图片输出文件失败: ${String(closeError)}`);
      }
      imagePackerApi.release();
    }
  }

  /**
   * 将PDF页面转换为图片
   * 
   * 使用 getPagePixelMap() 获取页面 PixelMap，然后直接打包写入目标文件，
   * 避免在内存中额外持有整块编码后的图片 buffer。
   */
  private async convertPageToImage(pageIndex: number, outputDir: string): Promise<PdfPageImage | null> {
    try {
      if (!this.pdfDocument) {
        return null;
      }

      logger.debug(TAG, `start converting page ${pageIndex + 1}`);
      
      // 获取PDF页面
      const pdfPage: pdfService.PdfPage = this.pdfDocument.getPage(pageIndex);
      if (!pdfPage) {
        logger.warn(TAG, `无法获取页面 ${pageIndex}`);
        return null;
      }

      const pageWidth = Math.max(1, Math.floor(pdfPage.getWidth()));
      const pageHeight = Math.max(1, Math.floor(pdfPage.getHeight()));

      let pixelMap: image.PixelMap | null = null;
      try {
        pixelMap = pdfPage.getPagePixelMap();
        if (!pixelMap) {
          logger.warn(TAG, `页面 ${pageIndex} 获取PixelMap失败`);
          return null;
        }

        let outputWidth = pageWidth;
        let outputHeight = pageHeight;
        try {
          const pixelMapInfo = pixelMap.getImageInfoSync();
          if (pixelMapInfo && pixelMapInfo.size) {
            outputWidth = pixelMapInfo.size.width;
            outputHeight = pixelMapInfo.size.height;
          }
        } catch (infoError) {
          logger.warn(TAG, `获取页面 ${pageIndex} PixelMap尺寸失败: ${String(infoError)}`);
        }

        logger.debug(
          TAG,
          `page ${pageIndex + 1} render size=${outputWidth}x${outputHeight}, source=${pageWidth}x${pageHeight}`
        );

        const finalPath = this.buildPageImagePath(outputDir, pageIndex);
        await this.writePixelMapToFile(pixelMap, finalPath, 'image/webp', 70);

        logger.debug(TAG, `page ${pageIndex + 1} converted: ${finalPath}`);

        // 获取文件信息
        let fileSize = 0;
        try {
          const stat = SafeFileUtils.statSync(finalPath);
          fileSize = stat.size;
        } catch (e) {
          // 忽略
        }

        return {
          pageIndex,
          imagePath: finalPath,
          width: outputWidth,
          height: outputHeight,
          fileSize
        };
      } finally {
        if (pixelMap) {
          try {
            pixelMap.release();
          } catch (error) {
            logger.warn(TAG, `释放PixelMap失败: ${String(error)}`);
          }
        }
      }

    } catch (error) {
      logger.error(TAG, `转换页面 ${pageIndex} 异常: ${error}`);
      return null;
    }
  }

  /**
   * 构建ComicInfo对象
   */
  private buildComicInfo(
    metadata: PdfMetadata,
    pageCount: number,
    mangaId: string,
    chapterId: string
  ): PdfComicInfo {
    const now = Date.now();
    const contentTypeTag = this.config.contentType === PdfContentType.EBOOK ? 'PDF电子书' : 'PDF漫画';

    return {
      // 基本信息
      title: metadata.title,
      series: metadata.title,
      number: '1',
      summary: metadata.description || `从PDF导入的${contentTypeTag}`,
      year: new Date().getFullYear(),
      month: new Date().getMonth() + 1,
      day: new Date().getDate(),
      
      // 作者信息
      writer: metadata.author,
      
      // 分类信息
      genre: contentTypeTag,
      tags: [contentTypeTag, 'PDF导入'],
      web: '',
      pageCount: pageCount,
      languageISO: 'zh',
      format: 'PDF',
      blackAndWhite: false,
      manga: this.config.contentType === PdfContentType.MANGA,
      
      // 内部使用字段
      _mangaId: mangaId,
      _chapterId: chapterId,
      _contentType: this.config.contentType
    };
  }

  /**
   * 写入ComicInfo.xml文件
   */
  private async writeComicInfoXml(chapterDir: string, comicInfo: PdfComicInfo): Promise<void> {
    try {
      const xmlContent = this.generateComicInfoXml(comicInfo);
      const xmlPath = `${chapterDir}/ComicInfo.xml`;

      const file = SafeFileUtils.openSync(xmlPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      const encoder = new TextEncoder();
      const buffer = encoder.encode(xmlContent);
      SafeFileUtils.writeSync(file.fd, buffer.buffer);
      SafeFileUtils.closeSync(file);

      logger.info(TAG, `ComicInfo.xml 已写入: ${xmlPath}`);
    } catch (error) {
      logger.error(TAG, `写入ComicInfo.xml失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 生成ComicInfo.xml内容
   */
  private generateComicInfoXml(info: PdfComicInfo): string {
    const escapeXml = (str: string | undefined): string => {
      if (!str) return '';
      return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&apos;');
    };

    const tagsStr = info.tags ? info.tags.join(',') : '';
    const mangaStr = info.manga ? 'Yes' : 'No';

    return `<?xml version="1.0" encoding="utf-8"?>
<ComicInfo xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <Title>${escapeXml(info.title)}</Title>
  <Series>${escapeXml(info.series)}</Series>
  <Number>${escapeXml(info.number)}</Number>
  <Summary>${escapeXml(info.summary)}</Summary>
  <Year>${info.year || ''}</Year>
  <Month>${info.month || ''}</Month>
  <Day>${info.day || ''}</Day>
  <Writer>${escapeXml(info.writer)}</Writer>
  <Genre>${escapeXml(info.genre)}</Genre>
  <Tags>${escapeXml(tagsStr)}</Tags>
  <PageCount>${info.pageCount || 0}</PageCount>
  <LanguageISO>${escapeXml(info.languageISO)}</LanguageISO>
  <Format>${escapeXml(info.format)}</Format>
  <Manga>${mangaStr}</Manga>
</ComicInfo>`;
  }

  /**
   * 生成封面图片
   */
  private async generateCover(
    mangaId: string,
    chapterDir: string,
    imageFiles: PdfPageImage[]
  ): Promise<string | null> {
    if (imageFiles.length === 0) {
      return null;
    }

    try {
      // 使用第一页作为封面
      const firstPage = imageFiles[0];
      const coverDir = `${this.config.outputDir}/${mangaId}`;
      const coverPath = `${coverDir}/cover${this.getImageExtension(firstPage.imagePath)}`;

      // 复制第一页图片作为封面
      SafeFileUtils.copyFileSync(firstPage.imagePath, coverPath);
      
      logger.info(TAG, `封面已生成: ${coverPath}`);
      return coverPath;

    } catch (error) {
      logger.warn(TAG, `生成封面失败: ${error}`);
      return null;
    }
  }

  private getImageExtension(filePath: string): string {
    const match = filePath.match(/(\.[^./\\]+)$/);
    return match ? match[1] : '.webp';
  }

  /**
   * 从文件路径获取文件名
   */
  private getFileNameFromPath(filePath: string): string {
    const parts = filePath.split('/');
    const encodedFileName = parts[parts.length - 1] || 'unknown.pdf';
    
    try {
      return decodeURIComponent(encodedFileName);
    } catch (error) {
      return encodedFileName;
    }
  }

  /**
   * 从文件名提取标题
   */
  private extractTitleFromFileName(fileName: string): string {
    // 移除文件扩展名
    const nameWithoutExt = fileName.replace(/\.pdf$/i, '');
    // 移除可能的特殊字符和数字后缀
    const cleanName = nameWithoutExt.replace(/[\[\]()（）【】_-]+$/, '').trim();
    return cleanName || '未知标题';
  }

  /**
   * 报告进度
   */
  private reportProgress(current: number, total: number, message: string): void {
    if (this.progressCallback) {
      this.progressCallback(current, total, message);
    }
    logger.debug(TAG, `进度: ${current}/${total} - ${message}`);
  }
}

/**
 * PDF元数据接口
 */
interface PdfMetadata {
  title: string;
  author: string;
  description: string;
  pageCount: number;
  pageWidth: number;
  pageHeight: number;
}

/**
 * TextEncoder polyfill for ArkTS
 */
class TextEncoder {
  encode(str: string): Uint8Array {
    const utf8: number[] = [];
    for (let i = 0; i < str.length; i++) {
      let charCode = str.charCodeAt(i);
      if (charCode < 0x80) {
        utf8.push(charCode);
      } else if (charCode < 0x800) {
        utf8.push(0xc0 | (charCode >> 6), 0x80 | (charCode & 0x3f));
      } else if (charCode < 0xd800 || charCode >= 0xe000) {
        utf8.push(0xe0 | (charCode >> 12), 0x80 | ((charCode >> 6) & 0x3f), 0x80 | (charCode & 0x3f));
      } else {
        // surrogate pair
        i++;
        charCode = 0x10000 + (((charCode & 0x3ff) << 10) | (str.charCodeAt(i) & 0x3ff));
        utf8.push(
          0xf0 | (charCode >> 18),
          0x80 | ((charCode >> 12) & 0x3f),
          0x80 | ((charCode >> 6) & 0x3f),
          0x80 | (charCode & 0x3f)
        );
      }
    }
    return new Uint8Array(utf8);
  }
}
