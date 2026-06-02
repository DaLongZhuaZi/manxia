import { SafeUtils } from '../../Utils/SafeUtils';
// 文件路径: src/main/ets/Framework/Compress/ComicArchiveManager.ets
/**
 * 漫画归档管理器
 * 基于@ohos.zlib实现.cbz漫画归档文件的生成和解压
 */

import { zlib } from '@kit.BasicServicesKit';
import { logger } from '../../Utils/Logger';
import { SandboxManager } from '../Storage/SandboxManager';
import { BusinessError } from '@kit.BasicServicesKit';
import { TimeUtils } from '../Utils/TimeUtils';
import { getFileExtension, getMimeTypeFromExtension } from '../../Utils/FileNameUtils';

const TAG = 'ComicArchiveManager';

export interface ComicChapterInfo {
  chapterId: string;
  chapterTitle: string;
  comicId: string;
  comicTitle: string;
  pageCount: number;
  pages: ComicPageInfo[];
}

export interface ComicPageInfo {
  pageIndex: number;
  fileName: string;
  filePath: string;
  fileSize: number;
  mimeType: string;
}

export interface ArchiveOptions {
  compressionLevel: zlib.CompressLevel;
  includeMetadata: boolean;
  metadataFormat: 'json' | 'xml';
}

export interface ArchiveMetadata {
  title: string;
  series: string;
  chapter: string;
  pageCount: number;
  createdAt: string;
  version: string;
}

export interface CbzFileInfo {
  fileSize: number;
  pageCount: number;
  metadata?: ArchiveMetadata;
}

export interface ArchiveStats {
  totalArchives: number;
  totalSize: number;
  averageSize: number;
}

export class ComicArchiveManager {
  private static instance: ComicArchiveManager | null = null;
  private sandboxManager: SandboxManager;
  
  // 默认归档选项
  private readonly defaultOptions: ArchiveOptions = {
    compressionLevel: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
    includeMetadata: true,
    metadataFormat: 'json'
  };

  // 支持的图片格式
  private readonly supportedImageFormats = [
    'image/jpeg',
    'image/jpg', 
    'image/png',
    'image/webp',
    'image/gif',
    'image/bmp'
  ];

  private constructor() {
    this.sandboxManager = SandboxManager.getInstance();
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): ComicArchiveManager {
    if (!ComicArchiveManager.instance) {
      ComicArchiveManager.instance = new ComicArchiveManager();
    }
    return ComicArchiveManager.instance;
  }

  /**
   * 创建CBZ漫画归档文件
   */
  public async createCbzArchive(
    chapterInfo: ComicChapterInfo,
    options?: Partial<ArchiveOptions>
  ): Promise<string> {
    try {
      const mergedOptions: ArchiveOptions = {
        compressionLevel: options?.compressionLevel ?? this.defaultOptions.compressionLevel,
        includeMetadata: options?.includeMetadata ?? this.defaultOptions.includeMetadata,
        metadataFormat: options?.metadataFormat ?? this.defaultOptions.metadataFormat
      };
      
      logger.info(TAG, `开始创建CBZ归档: ${chapterInfo.chapterTitle}`);
      
      // 验证章节信息
      this.validateChapterInfo(chapterInfo);
      
      // 准备临时工作目录
      const tempDir = await this.prepareTempDirectory(chapterInfo.chapterId);
      
      // 复制图片文件到临时目录
      await this.copyImagesToTemp(chapterInfo.pages, tempDir);
      
      // 生成元数据文件
      if (mergedOptions.includeMetadata) {
        await this.generateMetadata(chapterInfo, tempDir, mergedOptions.metadataFormat);
      }
      
      // 创建CBZ文件
      const cbzPath = await this.createZipArchive(chapterInfo, tempDir, mergedOptions);
      
      // 清理临时目录
      await this.cleanupTempDirectory(tempDir);
      
      logger.info(TAG, `CBZ归档创建完成: ${cbzPath}`);
      return cbzPath;
      
    } catch (error) {
      logger.error(TAG, '创建CBZ归档失败', error);
      throw error as Error;
    }
  }

  /**
   * 解压CBZ漫画归档文件
   */
  public async extractCbzArchive(cbzPath: string, extractDir?: string): Promise<ComicChapterInfo> {
    try {
      logger.info(TAG, `开始解压CBZ归档: ${cbzPath}`);
      
      // 验证CBZ文件存在
      if (!await this.sandboxManager.exists(cbzPath)) {
        throw new Error(`CBZ文件不存在: ${cbzPath}`);
      }
      
      // 准备解压目录
      const targetDir = extractDir || await this.prepareExtractDirectory(cbzPath);
      
      // 解压文件
      await this.extractZipArchive(cbzPath, targetDir);
      
      // 读取元数据
      const metadata = await this.readMetadata(targetDir);
      
      // 扫描图片文件
      const pages = await this.scanImageFiles(targetDir);
      
      // 构建章节信息
      const chapterInfo: ComicChapterInfo = {
        chapterId: metadata?.chapter || this.extractChapterIdFromPath(cbzPath),
        chapterTitle: metadata?.title || this.extractTitleFromPath(cbzPath),
        comicId: metadata?.series || '',
        comicTitle: metadata?.series || '',
        pageCount: pages.length,
        pages: pages
      };
      
      logger.info(TAG, `CBZ归档解压完成: ${targetDir}`);
      return chapterInfo;
      
    } catch (error) {
      logger.error(TAG, '解压CBZ归档失败', error);
      throw error as Error;
    }
  }

  /**
   * 验证CBZ文件完整性
   */
  public async validateCbzArchive(cbzPath: string): Promise<boolean> {
    try {
      // 检查文件存在
      if (!await this.sandboxManager.exists(cbzPath)) {
        return false;
      }
      
      // 尝试读取压缩文件信息
      const tempDir = await this.prepareExtractDirectory(cbzPath, true);
      
      try {
        await this.extractZipArchive(cbzPath, tempDir);
        const pages = await this.scanImageFiles(tempDir);
        
        // 清理临时目录
        await this.sandboxManager.deleteDirectory(tempDir, true);
        
        return pages.length > 0;
      } catch (error) {
        // 清理临时目录
        if (await this.sandboxManager.exists(tempDir)) {
          await this.sandboxManager.deleteDirectory(tempDir, true);
        }
        return false;
      }
      
    } catch (error) {
      logger.error(TAG, '验证CBZ文件失败', error);
      return false;
    }
  }

  /**
   * 获取CBZ文件信息
   */
  public async getCbzInfo(cbzPath: string): Promise<CbzFileInfo> {
    try {
      const fileInfo = await this.sandboxManager.getFileInfo(cbzPath);
      const tempDir = await this.prepareExtractDirectory(cbzPath, true);
      
      try {
        await this.extractZipArchive(cbzPath, tempDir);
        const pages = await this.scanImageFiles(tempDir);
        const metadata = await this.readMetadata(tempDir);
        
        // 清理临时目录
        await this.sandboxManager.deleteDirectory(tempDir, true);
        
        return {
          fileSize: fileInfo.size,
          pageCount: pages.length,
          metadata: metadata || undefined
        };
      } catch (error) {
        // 清理临时目录
        if (await this.sandboxManager.exists(tempDir)) {
          await this.sandboxManager.deleteDirectory(tempDir, true);
        }
        throw error as Error;
      }
      
    } catch (error) {
      logger.error(TAG, '获取CBZ文件信息失败', error);
      throw error as Error;
    }
  }

  /**
   * 验证章节信息
   */
  private validateChapterInfo(chapterInfo: ComicChapterInfo): void {
    if (!chapterInfo.chapterId) {
      throw new Error('章节ID不能为空');
    }
    
    if (!chapterInfo.pages || chapterInfo.pages.length === 0) {
      throw new Error('章节页面不能为空');
    }
    
    // 验证页面文件存在性
    for (const page of chapterInfo.pages) {
      if (!page.filePath) {
        throw new Error(`页面 ${page.pageIndex} 文件路径为空`);
      }
      
      if (!this.supportedImageFormats.includes(page.mimeType)) {
        throw new Error(`不支持的图片格式: ${page.mimeType}`);
      }
    }
  }

  /**
   * 准备临时工作目录
   */
  private async prepareTempDirectory(chapterId: string): Promise<string> {
    const tempDir = `${this.sandboxManager.getDirectory('temp')}/cbz_${chapterId}_${Date.now()}`;
    await this.sandboxManager.createDirectory(tempDir);
    return tempDir;
  }

  /**
   * 准备解压目录
   */
  private async prepareExtractDirectory(cbzPath: string, isTemp: boolean = false): Promise<string> {
    const fileName = cbzPath.substring(cbzPath.lastIndexOf('/') + 1, cbzPath.lastIndexOf('.'));
    const baseDir = isTemp ? this.sandboxManager.getDirectory('temp') : this.sandboxManager.getDirectory('chapters');
    const extractDir = `${baseDir}/${fileName}_${Date.now()}`;
    
    await this.sandboxManager.createDirectory(extractDir);
    return extractDir;
  }

  /**
   * 复制图片文件到临时目录
   */
  private async copyImagesToTemp(pages: ComicPageInfo[], tempDir: string): Promise<void> {
    try {
      // 按页面索引排序
      const sortedPages = pages.sort((a, b) => a.pageIndex - b.pageIndex);
      
      for (const page of sortedPages) {
        // 检查源文件是否存在
        if (!await this.sandboxManager.exists(page.filePath)) {
          throw new Error(`页面文件不存在: ${page.filePath}`);
        }
        
        // 生成目标文件名（确保按顺序排列）
        const paddedIndex = page.pageIndex.toString().padStart(4, '0');
        const extension = getFileExtension(page.fileName);
        const targetFileName = `${paddedIndex}.${extension}`;
        const targetPath = `${tempDir}/${targetFileName}`;
        
        // 复制文件
        await this.sandboxManager.copyFile(page.filePath, targetPath);
        
        logger.debug(TAG, `复制页面: ${page.filePath} -> ${targetPath}`);
      }
    } catch (error) {
      logger.error(TAG, '复制图片文件失败', error);
      throw error as Error;
    }
  }

  /**
   * 生成元数据文件
   */
  private async generateMetadata(
    chapterInfo: ComicChapterInfo,
    tempDir: string,
    format: 'json' | 'xml'
  ): Promise<void> {
    try {
      const metadata: ArchiveMetadata = {
        title: chapterInfo.chapterTitle,
        series: chapterInfo.comicTitle,
        chapter: chapterInfo.chapterId,
        pageCount: chapterInfo.pageCount,
        createdAt: TimeUtils.toISOString(Date.now()),
        version: '1.0'
      };
      
      let content: string;
      let fileName: string;
      
      if (format === 'json') {
        content = JSON.stringify(metadata, null, 2);
        fileName = 'metadata.json';
      } else {
        content = this.generateXmlMetadata(metadata);
        fileName = 'ComicInfo.xml';
      }
      
      const metadataPath = `${tempDir}/${fileName}`;
      await this.sandboxManager.writeFile(metadataPath, content);
      
      logger.debug(TAG, `生成元数据文件: ${metadataPath}`);
    } catch (error) {
      logger.error(TAG, '生成元数据文件失败', error);
      throw error as Error;
    }
  }

  /**
   * 生成XML格式元数据
   */
  private generateXmlMetadata(metadata: ArchiveMetadata): string {
    return `<?xml version="1.0" encoding="UTF-8"?>
<ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <Title>${this.escapeXml(metadata.title)}</Title>
  <Series>${this.escapeXml(metadata.series)}</Series>
  <Number>${this.escapeXml(metadata.chapter)}</Number>
  <PageCount>${metadata.pageCount}</PageCount>
  <Year>${new Date(metadata.createdAt).getFullYear()}</Year>
  <Month>${new Date(metadata.createdAt).getMonth() + 1}</Month>
  <Day>${new Date(metadata.createdAt).getDate()}</Day>
</ComicInfo>`;
  }

  /**
   * XML转义
   */
  private escapeXml(text: string): string {
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  /**
   * 创建ZIP归档文件
   */
  private async createZipArchive(
    chapterInfo: ComicChapterInfo,
    sourceDir: string,
    options: ArchiveOptions
  ): Promise<string> {
    try {
      // 生成CBZ文件路径
      const cbzFileName = this.generateCbzFileName(chapterInfo);
      const cbzPath = `${this.sandboxManager.getDirectory('chapters')}/${cbzFileName}`;
      
      // 使用zlib压缩目录
      await zlib.compressFile(sourceDir, cbzPath, {
        level: options.compressionLevel,
        memLevel: zlib.MemLevel.MEM_LEVEL_DEFAULT,
        strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY
      });
      
      logger.debug(TAG, `创建ZIP归档: ${sourceDir} -> ${cbzPath}`);
      return cbzPath;
      
    } catch (error) {
      logger.error(TAG, '创建ZIP归档失败', error);
      throw error as Error;
    }
  }

  /**
   * 解压ZIP归档文件
   */
  private async extractZipArchive(zipPath: string, targetDir: string): Promise<void> {
    try {
      await zlib.decompressFile(zipPath, targetDir);
      logger.debug(TAG, `解压ZIP归档: ${zipPath} -> ${targetDir}`);
    } catch (error) {
      logger.error(TAG, '解压ZIP归档失败', error);
      throw error as Error;
    }
  }

  /**
   * 读取元数据
   */
  private async readMetadata(dir: string): Promise<ArchiveMetadata | null> {
    try {
      // 尝试读取JSON元数据
      const jsonPath = `${dir}/metadata.json`;
      if (await this.sandboxManager.exists(jsonPath)) {
        const content = await this.sandboxManager.readTextFile(jsonPath);
        return SafeUtils.parseObj(content) as ArchiveMetadata;
      }
      
      // 尝试读取XML元数据
      const xmlPath = `${dir}/ComicInfo.xml`;
      if (await this.sandboxManager.exists(xmlPath)) {
        const content = await this.sandboxManager.readTextFile(xmlPath);
        return this.parseXmlMetadata(content);
      }
      
      return null;
    } catch (error) {
      logger.error(TAG, '读取元数据失败', error);
      return null;
    }
  }

  /**
   * 解析XML元数据
   */
  private parseXmlMetadata(xmlContent: string): ArchiveMetadata {
    // 简单的XML解析（实际项目中可能需要更完善的XML解析器）
    const extractValue = (tag: string): string => {
      const regex = new RegExp(`<${tag}>(.*?)</${tag}>`, 'i');
      const match = xmlContent.match(regex);
      return match ? match[1] : '';
    };
    
    return {
      title: extractValue('Title'),
      series: extractValue('Series'),
      chapter: extractValue('Number'),
      pageCount: parseInt(extractValue('PageCount')) || 0,
      createdAt: TimeUtils.toISOString(Date.now()),
      version: '1.0'
    };
  }

  /**
   * 扫描图片文件
   */
  private async scanImageFiles(dir: string): Promise<ComicPageInfo[]> {
    try {
      const files = await this.sandboxManager.listDirectory(dir);
      const imageFiles: ComicPageInfo[] = [];
      
      for (const file of files) {
        const filePath = `${dir}/${file}`;
        const fileInfo = await this.sandboxManager.getFileInfo(filePath);
        
        // 检查是否为图片文件
        const mimeType = getMimeTypeFromExtension(getFileExtension(file));
        if (this.supportedImageFormats.includes(mimeType)) {
          // 从文件名提取页面索引
          const pageIndex = this.extractPageIndexFromFileName(file);
          
          imageFiles.push({
            pageIndex: pageIndex,
            fileName: file,
            filePath: filePath,
            fileSize: fileInfo.size,
            mimeType: mimeType
          });
        }
      }
      
      // 按页面索引排序
      return imageFiles.sort((a, b) => a.pageIndex - b.pageIndex);
    } catch (error) {
      logger.error(TAG, '扫描图片文件失败', error);
      throw error as Error;
    }
  }

  /**
   * 生成CBZ文件名
   */
  private generateCbzFileName(chapterInfo: ComicChapterInfo): string {
    const safeTitle = this.sanitizeFileName(chapterInfo.chapterTitle);
    const timestamp = TimeUtils.toISOString(Date.now()).replace(/[:.]/g, '-');
    return `${safeTitle}_${timestamp}.cbz`;
  }

  /**
   * 清理文件名中的非法字符
   */
  private sanitizeFileName(fileName: string): string {
    return fileName.replace(/[<>:"/\\|?*]/g, '_').trim();
  }


  /**
   * 从文件名提取页面索引
   */
  private extractPageIndexFromFileName(fileName: string): number {
    const nameWithoutExt = fileName.substring(0, fileName.lastIndexOf('.'));
    const match = nameWithoutExt.match(/(\d+)/);
    return match ? parseInt(match[1]) : 0;
  }

  /**
   * 从路径提取章节ID
   */
  private extractChapterIdFromPath(path: string): string {
    const fileName = path.substring(path.lastIndexOf('/') + 1, path.lastIndexOf('.'));
    return fileName;
  }

  /**
   * 从路径提取标题
   */
  private extractTitleFromPath(path: string): string {
    const fileName = path.substring(path.lastIndexOf('/') + 1, path.lastIndexOf('.'));
    return fileName.replace(/_/g, ' ');
  }

  /**
   * 清理临时目录
   */
  private async cleanupTempDirectory(tempDir: string): Promise<void> {
    try {
      if (await this.sandboxManager.exists(tempDir)) {
        await this.sandboxManager.deleteDirectory(tempDir, true);
        logger.debug(TAG, `清理临时目录: ${tempDir}`);
      }
    } catch (error) {
      logger.error(TAG, '清理临时目录失败', error);
    }
  }

  /**
   * 获取归档统计信息
   */
  public async getArchiveStats(): Promise<ArchiveStats> {
    try {
      const chaptersDir = this.sandboxManager.getDirectory('chapters');
      const files = await this.sandboxManager.listDirectory(chaptersDir);
      
      let totalSize = 0;
      let archiveCount = 0;
      
      for (const file of files) {
        if (file.endsWith('.cbz')) {
          const filePath = `${chaptersDir}/${file}`;
          const fileInfo = await this.sandboxManager.getFileInfo(filePath);
          totalSize += fileInfo.size;
          archiveCount++;
        }
      }
      
      return {
        totalArchives: archiveCount,
        totalSize: totalSize,
        averageSize: archiveCount > 0 ? totalSize / archiveCount : 0
      };
    } catch (error) {
      logger.error(TAG, '获取归档统计信息失败' + String(error));
      throw error as Error;
    }
  }
}