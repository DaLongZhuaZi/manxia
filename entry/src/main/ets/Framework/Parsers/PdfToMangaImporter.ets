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

/**
 * 批量大小：每处理多少页后强制让出更长时间
 */
const BATCH_SIZE = 3;

/**
 * 每页转换前后的延时（毫秒）
 * 这个延时让系统有机会处理其他事件，避免watchdog检测到线程阻塞
 */
const PAGE_DELAY_MS = 100;

/**
 * 每批次之间的额外延时（毫秒）
 * 更长的延时确保系统有足够时间响应
 */
const BATCH_DELAY_MS = 300;
const MANGA_RENDER_BASE_SCALE = 2.2;
const EBOOK_RENDER_BASE_SCALE = 2.0;
const MANGA_MAX_RENDER_LONG_EDGE = 2400;
const EBOOK_MAX_RENDER_LONG_EDGE = 2200;

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
export interface PdfRenderSize {
  bitmapWidth: number;
  bitmapHeight: number;
  rotation: number;
}

export type PdfImportProgressCallback = (current: number, total: number, message: string) => void;

/**
 * PDF转漫画导入器类
 */
export class PdfToMangaImporter {
  private pdfDocument: pdfService.PdfDocument | null = null;
  private config: PdfImportConfig;
  private progressCallback?: PdfImportProgressCallback;

  constructor(config: PdfImportConfig, progressCallback?: PdfImportProgressCallback) {
    this.config = config;
    this.progressCallback = progressCallback;
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
      // 注意：convertToImage是同步阻塞操作，为避免触发THREAD_BLOCK_6S，
      // 我们采用分批处理+延时的方式，让系统有机会处理其他事件
      const pageCount = this.pdfDocument!.getPageCount();
      const imageFiles: PdfPageImage[] = [];
      
      logger.info(TAG, `开始转换 ${pageCount} 页PDF，预计需要较长时间...`);
      
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
        
        // 每处理BATCH_SIZE页后，添加额外的延时让系统有更多时间响应
        if ((i + 1) % BATCH_SIZE === 0 && i < pageCount - 1) {
          logger.info(TAG, `已完成 ${i + 1}/${pageCount} 页，暂停让系统响应...`);
          await delay(BATCH_DELAY_MS);
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
      try {
        this.pdfDocument?.releaseDocument();
      } catch (error) {
        logger.warn(TAG, `释放PDF文档失败: ${String(error)}`);
      }
      this.pdfDocument = null;
    }
  }

  /**
   * 加载PDF文档
   */
  private async loadPdfDocument(): Promise<PdfImportResult> {
    try {
      this.pdfDocument = new pdfService.PdfDocument();
      const loadResult = this.pdfDocument.loadDocument(this.config.pdfPath);

      if (loadResult !== pdfService.ParseResult.PARSE_SUCCESS) {
        return {
          success: false,
          errorMessage: `PDF加载失败，错误码: ${loadResult}`
        };
      }

      const pageCount = this.pdfDocument.getPageCount();
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
        fileIo.mkdirSync(mangaDir, true);
      } catch (e) {
        // 目录可能已存在
      }

      // 创建章节目录
      try {
        fileIo.mkdirSync(chapterDir, true);
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
   * 将PixelMap转换为图片Buffer
   * 使用ImagePacker的异步方法，不会阻塞主线程
   */
  private async pixelMapToBuffer(pixelMap: image.PixelMap, format: string = 'image/jpeg', quality: number = 90): Promise<ArrayBuffer> {
    const packOpts: image.PackingOption = {
      format: format,
      quality: quality
    };
    const imagePackerApi = image.createImagePacker();
    try {
      const buffer = await imagePackerApi.packToData(pixelMap, packOpts);
      return buffer;
    } finally {
      imagePackerApi.release();
    }
  }

  /**
   * 将PDF页面转换为图片
   * 
   * 使用getPagePixelMap()获取页面PixelMap，然后使用ImagePacker异步打包为图片文件。
   * 这种方式比convertToImage()更不容易阻塞主线程，因为：
   * 1. getPagePixelMap()获取的是内存中的像素数据
   * 2. ImagePacker.packToData()是异步操作
   * 3. 文件写入使用异步API
   */
  private async convertPageToImage(pageIndex: number, outputDir: string): Promise<PdfPageImage | null> {
    try {
      if (!this.pdfDocument) {
        return null;
      }

      // 在转换前添加短暂延时，让UI有机会响应
      await delay(PAGE_DELAY_MS);

      logger.info(TAG, `开始转换页面 ${pageIndex}`);
      
      // 获取PDF页面
      const pdfPage: pdfService.PdfPage = this.pdfDocument.getPage(pageIndex);
      if (!pdfPage) {
        logger.warn(TAG, `无法获取页面 ${pageIndex}`);
        return null;
      }

      const pageWidth = Math.max(1, Math.floor(pdfPage.getWidth()));
      const pageHeight = Math.max(1, Math.floor(pdfPage.getHeight()));
      const renderSize = this.resolveRenderSize(pdfPage, pageWidth, pageHeight);
      const matrix = new pdfService.PdfMatrix();
      matrix.x = 0;
      matrix.y = 0;
      matrix.width = pageWidth;
      matrix.height = pageHeight;
      matrix.rotate = renderSize.rotation;

      logger.info(
        TAG,
        `页面 ${pageIndex} 使用受控渲染尺寸: ${renderSize.bitmapWidth}x${renderSize.bitmapHeight}, 原始=${pageWidth}x${pageHeight}, rotation=${renderSize.rotation}`
      );

      let pixelMap: image.PixelMap | null = null;
      try {
        pixelMap = pdfPage.getAreaPixelMap(
          matrix,
          renderSize.bitmapWidth,
          renderSize.bitmapHeight,
          false,
          true
        );
        if (!pixelMap) {
          logger.warn(TAG, `页面 ${pageIndex} 获取PixelMap失败`);
          return null;
        }

        // 使用受控渲染尺寸降低超大扫描PDF的内存峰值
        const imgBuffer = await this.pixelMapToBuffer(pixelMap, 'image/webp', 70);

        // 生成输出文件路径
        const outputFileName = `page_${pageIndex}.webp`;
        const outputPath = `${outputDir}/${outputFileName}`;

        // 异步写入文件
        const file = fileIo.openSync(outputPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try {
          await fileIo.write(file.fd, imgBuffer);
        } finally {
          fileIo.closeSync(file.fd);
        }

        logger.info(TAG, `页面 ${pageIndex} 转换成功: ${outputPath}`);

        // 转换后添加短暂延时
        await delay(PAGE_DELAY_MS);

        // 重命名为标准格式: page_0001.webp
        const standardName = `page_${String(pageIndex).padStart(4, '0')}.webp`;
        const standardPath = `${outputDir}/${standardName}`;

        let finalPath = outputPath;
        if (outputPath !== standardPath) {
          try {
            fileIo.renameSync(outputPath, standardPath);
            finalPath = standardPath;
          } catch (e) {
            logger.warn(TAG, `重命名文件失败: ${e}`);
          }
        }

        // 获取文件信息
        let fileSize = 0;
        try {
          const stat = fileIo.statSync(finalPath);
          fileSize = stat.size;
        } catch (e) {
          // 忽略
        }

        return {
          pageIndex,
          imagePath: finalPath,
          width: renderSize.bitmapWidth,
          height: renderSize.bitmapHeight,
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

  private resolveRenderSize(
    pdfPage: pdfService.PdfPage,
    pageWidth: number,
    pageHeight: number
  ): PdfRenderSize {
    const baseScale = this.config.contentType === PdfContentType.MANGA
      ? MANGA_RENDER_BASE_SCALE
      : EBOOK_RENDER_BASE_SCALE;
    const maxLongEdge = this.config.contentType === PdfContentType.MANGA
      ? MANGA_MAX_RENDER_LONG_EDGE
      : EBOOK_MAX_RENDER_LONG_EDGE;
    const rotation = Number(pdfPage.getRotation());

    let bitmapWidth = Math.max(1, Math.floor(pageWidth * baseScale));
    let bitmapHeight = Math.max(1, Math.floor(pageHeight * baseScale));
    const currentLongEdge = Math.max(bitmapWidth, bitmapHeight);
    if (currentLongEdge > maxLongEdge) {
      const downscale = maxLongEdge / currentLongEdge;
      bitmapWidth = Math.max(1, Math.floor(bitmapWidth * downscale));
      bitmapHeight = Math.max(1, Math.floor(bitmapHeight * downscale));
    }

    if (rotation === 90 || rotation === 270) {
      const swappedWidth = bitmapHeight;
      bitmapHeight = bitmapWidth;
      bitmapWidth = swappedWidth;
    }

    const renderSize: PdfRenderSize = {
      bitmapWidth,
      bitmapHeight,
      rotation
    };
    return renderSize;
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

      const file = fileIo.openSync(xmlPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      const encoder = new TextEncoder();
      const buffer = encoder.encode(xmlContent);
      fileIo.writeSync(file.fd, buffer.buffer);
      fileIo.closeSync(file);

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
      const coverPath = `${coverDir}/cover.png`;

      // 复制第一页图片作为封面
      fileIo.copyFileSync(firstPage.imagePath, coverPath);
      
      logger.info(TAG, `封面已生成: ${coverPath}`);
      return coverPath;

    } catch (error) {
      logger.warn(TAG, `生成封面失败: ${error}`);
      return null;
    }
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
