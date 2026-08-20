import { SafeFileUtils } from '../Utils/SafeFileUtils';
/**
 * 通用解压缩工具类
 * 用于数据管理功能中的文件解压缩操作
 * 
 * 支持的格式：
 * - ZIP/CBZ: 优先使用系统@ohos.zlib，密码包/编码异常时回退到@ohos/minizip
 * - RAR/CBR/7Z/LZMA/TAR/GZ/BZ2/XZ: 使用@ohos/oh7zip
 */

import { zlib } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { logger } from './Logger';
import { SandboxManager } from '../Framework/Storage/SandboxManager';
import { BusinessError } from '@kit.BasicServicesKit';
import { getMimeTypeFromExtension } from './FileNameUtils';
import { Uncompress, Config7z } from '@ohos/oh7zip';
import { MinizipNative } from '@ohos/minizip';
import fs from '@ohos.file.fs';

const TAG = 'CompressionUtils';

/**
 * 解压缩选项接口
 */
export interface ExtractionOptions {
  /** 目标目录，如果不指定则自动生成 */
  targetDirectory?: string;
  /** 是否覆盖已存在的文件 */
  overwrite?: boolean;
  /** 是否创建子目录（以压缩文件名命名） */
  createSubDirectory?: boolean;
  /** 文件过滤器，返回true表示提取该文件 */
  fileFilter?: (fileName: string) => boolean;
  /** 最大提取文件数量限制 */
  maxFiles?: number;
  /** 最大提取文件大小限制（字节） */
  maxTotalSize?: number;
  password?: string;
}

/**
 * 解压缩结果接口
 */
export interface ExtractionResult {
  /** 解压缩是否成功 */
  success: boolean;
  /** 解压缩目标目录 */
  extractedPath: string;
  /** 提取的文件列表 */
  extractedFiles: string[];
  /** 提取的文件总数 */
  fileCount: number;
  /** 提取的文件总大小 */
  totalSize: number;
  /** 错误信息（如果失败） */
  error?: string;
  /** 警告信息 */
  warnings: string[];
}

/**
 * 文件信息接口
 */
export interface ExtractedFileInfo {
  /** 文件名 */
  fileName: string;
  /** 完整路径 */
  filePath: string;
  /** 文件大小 */
  fileSize: number;
  /** 文件类型 */
  mimeType: string;
  /** 是否为图片文件 */
  isImage: boolean;
  /** 是否为XML文件 */
  isXml: boolean;
}

/**
 * 包含ComicInfo.xml内容的解压缩结果接口
 */
export interface ExtractionResultWithComicInfo {
  /** 解压缩结果 */
  result: ExtractionResult;
  /** ComicInfo.xml文件内容 */
  comicInfoContent?: string;
}

/**
 * 递归解压结果接口
 */
export interface RecursiveExtractionResult {
  /** 最终解压路径（最底层有效目录） */
  finalPath: string;
  /** 是否找到XML文件 */
  foundXml: boolean;
  /** ComicInfo.xml文件内容 */
  comicInfoContent?: string;
  /** 解压的总文件数 */
  totalFiles: number;
  /** 递归解压的层数 */
  recursionDepth: number;
  /** 临时目录列表（需要清理） */
  tempDirectories: string[];
  /** 警告信息 */
  warnings: string[];
}

/**
 * 递归解压内部结果接口
 */
interface RecursiveExtractionInternalResult {
  /** 解压路径 */
  extractedPath: string;
  /** 总文件数 */
  totalFiles: number;
  /** 递归深度 */
  recursionDepth: number;
}

/**
 * 通用解压缩工具类
 */
export class CompressionUtils {
  private static instance: CompressionUtils | null = null;
  private sandboxManager: SandboxManager;
  private tempCopySequence: number = 0;

  // 支持的压缩文件格式
  private readonly supportedArchiveFormats = ['.zip', '.cbz', '.tar', '.gz', '.tgz', '.bz2', '.xz', '.rar', '.cbr', '.7z', '.lzma'];
  private readonly zlibFormats = ['.zip', '.cbz'];
  private readonly commonsCompressFormats = ['.tar', '.gz', '.tgz', '.bz2', '.xz'];
  private readonly unrarFormats = ['.rar', '.cbr'];
  private readonly sevenZipFormats = ['.7z', '.lzma'];
  private readonly zipEncodingCandidates: Array<number | undefined> = [undefined, 65001, 936, 950, 932, 437];

  // 支持的图片格式
  private readonly supportedImageFormats = [
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
    'image/gif',
    'image/bmp'
  ];

  // 默认解压缩选项
  private readonly defaultOptions: ExtractionOptions = {
    overwrite: true,
    createSubDirectory: true,
    maxFiles: 1000,
    maxTotalSize: 500 * 1024 * 1024 // 500MB
  };

  private constructor() {
    this.sandboxManager = SandboxManager.getInstance();
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): CompressionUtils {
    if (!CompressionUtils.instance) {
      CompressionUtils.instance = new CompressionUtils();
    }
    return CompressionUtils.instance;
  }

  /**
   * 解压缩文件到指定目录
   * @param archivePath 压缩文件路径
   * @param options 解压缩选项
   * @returns 解压缩结果
   */
  public async extractArchive(
    archivePath: string,
    options?: Partial<ExtractionOptions>
  ): Promise<ExtractionResult> {
    // 修复扩展运算符错误：使用显式属性赋值替代扩展运算符
    const mergedOptions: ExtractionOptions = {
      targetDirectory: options?.targetDirectory || this.defaultOptions.targetDirectory,
      overwrite: options?.overwrite !== undefined ? options.overwrite : this.defaultOptions.overwrite!,
      createSubDirectory: options?.createSubDirectory !== undefined ? options.createSubDirectory : this.defaultOptions.createSubDirectory!,
      fileFilter: options?.fileFilter || this.defaultOptions.fileFilter,
      maxFiles: options?.maxFiles || this.defaultOptions.maxFiles!,
      maxTotalSize: options?.maxTotalSize || this.defaultOptions.maxTotalSize!,
      password: options?.password
    };

    const result: ExtractionResult = {
      success: false,
      extractedPath: '',
      extractedFiles: [],
      fileCount: 0,
      totalSize: 0,
      warnings: []
    };
    let actualFilePath: string = archivePath;

    try {
      logger.info(TAG, `开始解压缩文件: ${archivePath}`);

      // 验证输入文件并获取实际文件路径
      actualFilePath = await this.validateArchiveFile(archivePath);

      // 准备解压缩目录
      const targetDir = await this.prepareExtractionDirectory(archivePath, mergedOptions);
      result.extractedPath = targetDir;

      // 执行解压缩
      await this.performExtractionEnhanced(actualFilePath, targetDir, mergedOptions, result);

      // 扫描解压缩后的文件
      const fileInfos = await this.scanExtractedFiles(targetDir, mergedOptions);
      result.extractedFiles = fileInfos.map(info => info.filePath);
      result.fileCount = fileInfos.length;
      result.totalSize = fileInfos.reduce((sum, info) => sum + info.fileSize, 0);

      result.success = true;
      logger.info(TAG, `解压缩完成: ${result.fileCount} 个文件, 总大小: ${result.totalSize} 字节`);
    } catch (error) {
      result.error = String(error);
      const errorStr = String(error);
      logger.error(TAG, '解压缩失败', errorStr);
      if (result.extractedPath.length > 0) {
        try {
          await this.sandboxManager.deleteDirectory(result.extractedPath, true);
          result.extractedPath = '';
        } catch (cleanupError) {
          logger.warn(TAG, `清理解压失败目录失败: ${result.extractedPath}`, String(cleanupError));
        }
      }
    } finally {
      // Picker URI 会先复制到沙箱；无论解压成功或失败都必须释放该临时副本。
      if (actualFilePath !== archivePath) {
        try {
          await this.sandboxManager.deleteFile(actualFilePath);
          logger.debug(TAG, `清理临时文件: ${actualFilePath}`);
        } catch (cleanupError) {
          logger.warn(TAG, `清理临时文件失败: ${actualFilePath}`, String(cleanupError));
        }
      }
    }

    return result;
  }

  /**
   * 解压缩并查找ComicInfo.xml文件
   * @param archivePath 压缩文件路径
   * @param options 解压缩选项
   * @returns 解压缩结果和ComicInfo.xml内容
   */
  public async extractAndFindComicInfo(
    archivePath: string,
    options?: Partial<ExtractionOptions>
  ): Promise<ExtractionResultWithComicInfo> {
    try {
      // 修复扩展运算符错误：使用显式属性赋值替代扩展运算符
      const extractOptions: Partial<ExtractionOptions> = {
        targetDirectory: options?.targetDirectory,
        overwrite: options?.overwrite,
        createSubDirectory: options?.createSubDirectory,
        maxFiles: options?.maxFiles,
        maxTotalSize: options?.maxTotalSize,
        password: options?.password,
        fileFilter: (fileName: string) => {
          const lowerName = fileName.toLowerCase();
          return lowerName.endsWith('.xml') || 
                 lowerName.endsWith('.jpg') || 
                 lowerName.endsWith('.jpeg') || 
                 lowerName.endsWith('.png') || 
                 lowerName.endsWith('.webp') || 
                 lowerName.endsWith('.gif') || 
                 lowerName.endsWith('.bmp');
        }
      };

      const result = await this.extractArchive(archivePath, extractOptions);

      if (!result.success) {
        const returnResult: ExtractionResultWithComicInfo = { result };
        return returnResult;
      }

      // 查找ComicInfo.xml文件
      const comicInfoPath = await this.findComicInfoFile(result.extractedPath);
      let comicInfoContent: string | undefined;

      if (comicInfoPath) {
        try {
          comicInfoContent = SafeFileUtils.readTextSync(comicInfoPath);
          logger.info(TAG, `找到ComicInfo.xml文件: ${comicInfoPath}`);
        } catch (error) {
          result.warnings.push(`读取ComicInfo.xml失败: ${error}`);
          const errorStr = String(error);
          logger.warn(TAG, '读取ComicInfo.xml失败', errorStr);
        }
      } else {
        result.warnings.push('未找到ComicInfo.xml文件');
        logger.warn(TAG, '未找到ComicInfo.xml文件');
      }

      const returnResult: ExtractionResultWithComicInfo = { result, comicInfoContent };
      return returnResult;

    } catch (error) {
      const errorStr = String(error);
      logger.error(TAG, '解压缩并查找ComicInfo.xml失败', errorStr);
      throw error as Error;
    }
  }

  /**
   * 将URI路径转换为本地文件系统路径或处理URI访问
   * @param uriPath URI格式的路径
   * @returns 本地文件系统路径或URI
   */
  private convertUriToLocalPath(uriPath: string): string {
    try {
      // 如果是file://协议的URI，需要转换为本地路径
      if (uriPath.startsWith('file://')) {
        // 移除file://前缀
        let localPath = uriPath.substring(7);
        
        // 解码URL编码的字符
        localPath = decodeURIComponent(localPath);
        
        // 在HarmonyOS中，file://协议通常指向沙箱路径
        // 需要根据实际情况调整路径映射
        logger.debug(TAG, `URI转换: ${uriPath} -> ${localPath}`);
        
        return localPath;
      }
      
      // 如果不是URI格式，直接返回
      return uriPath;
    } catch (error) {
      const errorStr = String(error);
      logger.warn(TAG, `URI路径转换失败: ${uriPath}`, errorStr);
      return uriPath;
    }
  }

  /**
   * 复制URI文件到临时目录
   * @param uriPath URI路径
   * @returns 临时文件路径
   */
  private async copyUriFileToTemp(uriPath: string): Promise<string> {
    let tempFilePath: string = '';
    let sourceFile: fileIo.File | null = null;
    try {
      // 生成临时文件路径
      const fileName: string = this.sanitizeTemporaryFileName(this.getFileNameFromUri(uriPath));
      const timestamp = Date.now();
      this.tempCopySequence += 1;
      const tempDir = this.sandboxManager.getDirectory('temp');
      tempFilePath = `${tempDir}/temp_${timestamp}_${this.tempCopySequence}_${fileName}`;
      
      // 确保临时目录存在
      await this.sandboxManager.createDirectory(tempDir);
      
      // 先打开 Picker URI 取得临时只读权限，再让系统按 FD 流式复制。
      // 避免按整个 CBZ 大小分配 ArrayBuffer，批量导入时不会叠加大块 JS 堆内存。
      sourceFile = await fileIo.open(uriPath, fileIo.OpenMode.READ_ONLY);
      const sourceStat = await fileIo.stat(sourceFile.fd);
      const fileSize: number = sourceStat.size;

      if (fileSize === 0) {
        throw new Error('选择的文件为空');
      }

      const maxFileSize: number = 1024 * 1024 * 1024;
      if (fileSize > maxFileSize) {
        throw new Error(`文件过大: ${(fileSize / 1024 / 1024).toFixed(2)}MB，最大支持: 1GB`);
      }

      await fileIo.copyFile(sourceFile.fd, tempFilePath);
      const copiedStat = await fileIo.stat(tempFilePath);
      if (copiedStat.size !== fileSize) {
        throw new Error(`文件复制不完整: 期望 ${fileSize} 字节，实际复制 ${copiedStat.size} 字节`);
      }

      logger.debug(TAG, `URI文件复制到临时目录: ${uriPath} -> ${tempFilePath}, 大小: ${fileSize} bytes`);
      return tempFilePath;
    } catch (error) {
      const errorStr = String(error);
      logger.error(TAG, `复制URI文件失败: ${uriPath}`, errorStr);

      if (tempFilePath.length > 0) {
        try {
          await this.sandboxManager.deleteFile(tempFilePath);
        } catch (cleanupError) {
          logger.debug(TAG, `清理未完成URI临时副本失败: ${tempFilePath}, ${String(cleanupError)}`);
        }
      }
      
      // 提供更友好的错误信息
      if (errorStr.includes('Permission denied') || errorStr.includes('Operation not permitted')) {
        throw new Error(`没有权限访问文件: ${this.getFileNameFromUri(uriPath)}`);
      } else if (errorStr.includes('No such file')) {
        throw new Error(`文件不存在或已被移动: ${this.getFileNameFromUri(uriPath)}`);
      } else if (errorStr.includes('No space left')) {
        throw new Error('设备存储空间不足，无法复制文件');
      } else {
        throw new Error(`无法访问文件: ${this.getFileNameFromUri(uriPath)} (${errorStr})`);
      }
    } finally {
      if (sourceFile !== null) {
        try {
          await fileIo.close(sourceFile);
        } catch (closeError) {
          logger.warn(TAG, `关闭Picker文件失败: ${this.getFileNameFromUri(uriPath)}`, String(closeError));
        }
      }
    }
  }

  /**
   * 从URI中提取文件名
   * @param uri URI路径
   * @returns 文件名
   */
  private getFileNameFromUri(uri: string): string {
    try {
      const parts = uri.split('/');
      let fileName = parts[parts.length - 1] || 'unknown_file';
      
      // 解码URL编码的文件名
      fileName = decodeURIComponent(fileName);
      
      return fileName;
    } catch (error) {
      const errorStr = String(error);
      logger.warn(TAG, `解析文件名失败: ${uri}`, errorStr);
      return 'unknown_file';
    }
  }

  /**
   * URI 文件名可能在 URL 解码后重新包含路径分隔符。临时副本只能使用
   * 单一 basename，避免 ../ 或编码后的斜杠逃出临时目录。
   */
  private sanitizeTemporaryFileName(fileName: string): string {
    let safeName: string = fileName
      .replace(/[\\/:*?"<>|]/g, '_')
      .replace(/\.\./g, '_')
      .trim();
    if (safeName.length <= 0 || safeName === '.' || safeName === '..') {
      safeName = 'archive.cbz';
    }
    return safeName;
  }

  /**
   * 验证压缩文件
   * @param archivePath 压缩文件路径
   */
  private async validateArchiveFile(archivePath: string): Promise<string> {
    let actualFilePath: string = archivePath; // 初始化为原始路径
    let isTemporaryFile: boolean = false; // 标记是否为临时文件
    
    try {
      // 如果是URI路径，先复制到临时目录
      if (archivePath.startsWith('file://')) {
        actualFilePath = await this.copyUriFileToTemp(archivePath);
        isTemporaryFile = true;
      }
      
      // 检查文件是否存在
      if (!await this.sandboxManager.exists(actualFilePath)) {
        throw new Error(`压缩文件不存在: ${archivePath}`);
      }

      // 检查文件扩展名
      const extension = this.getFileExtension(actualFilePath);
      if (!this.supportedArchiveFormats.includes(extension)) {
        throw new Error(`不支持的压缩文件格式: ${extension}`);
      }

      // 检查文件大小
      const fileInfo = await this.sandboxManager.getFileInfo(actualFilePath);
      if (fileInfo.size === 0) {
        throw new Error('压缩文件为空');
      }

      // 检查文件大小限制（最大1GB）
      const maxFileSize = 1024 * 1024 * 1024; // 1GB
      if (fileInfo.size > maxFileSize) {
        throw new Error(`压缩文件过大: ${fileInfo.size} 字节，最大支持: ${maxFileSize} 字节`);
      }
      
      return actualFilePath;
    } catch (error) {
      // 如果复制了临时文件但验证失败，清理临时文件
      if (isTemporaryFile && actualFilePath !== archivePath) {
        try {
          await this.sandboxManager.deleteFile(actualFilePath);
          logger.debug(TAG, `已清理临时文件: ${actualFilePath}`);
        } catch (cleanupError) {
          const cleanupErrorStr = String(cleanupError);
          logger.warn(TAG, `清理临时文件失败: ${actualFilePath}`, cleanupErrorStr);
        }
      }
      
      // 提供更友好的错误信息
      const errorStr = String(error);
      const fileName = this.getFileNameFromUri(archivePath);
      
      if (errorStr.includes('压缩文件不存在')) {
        throw new Error(`找不到文件: ${fileName}`);
      } else if (errorStr.includes('不支持的压缩文件格式')) {
        const extension = this.getFileExtension(actualFilePath);
        throw new Error(`不支持的文件格式: ${extension}，请选择 ${this.supportedArchiveFormats.join(', ')} 格式的文件`);
      } else if (errorStr.includes('压缩文件为空')) {
        throw new Error(`文件为空: ${fileName}`);
      } else if (errorStr.includes('压缩文件过大')) {
        throw new Error(`文件过大: ${fileName}，最大支持 1GB`);
      } else {
        throw error as Error;
      }
    }
  }

  /**
   * 准备解压缩目录
   * @param archivePath 压缩文件路径
   * @param options 解压缩选项
   * @returns 目标目录路径
   */
  private async prepareExtractionDirectory(
    archivePath: string,
    options: ExtractionOptions
  ): Promise<string> {
    let targetDir: string;

    if (options.targetDirectory) {
      targetDir = options.targetDirectory;
    } else {
      // 转换URI路径为本地路径以获取正确的文件名
      const localPath = this.convertUriToLocalPath(archivePath);
      
      // 自动生成目录名
      const fileName = this.getFileNameWithoutExtension(localPath);
      const timestamp = Date.now();
      const baseDir = this.sandboxManager.getDirectory('temp');
      
      if (options.createSubDirectory) {
        targetDir = `${baseDir}/extracted_${fileName}_${timestamp}`;
      } else {
        targetDir = `${baseDir}/extracted_${timestamp}`;
      }
    }

    // 创建目录
    if (await this.sandboxManager.exists(targetDir)) {
      if (options.overwrite) {
        await this.sandboxManager.deleteDirectory(targetDir, true);
      } else {
        throw new Error(`目标目录已存在: ${targetDir}`);
      }
    }

    await this.sandboxManager.createDirectory(targetDir);
    logger.debug(TAG, `准备解压缩目录: ${targetDir}`);

    return targetDir;
  }

  /**
   * 执行解压缩操作
   * @param archivePath 压缩文件路径（已经是实际的本地路径）
   * @param targetDir 目标目录
   * @param options 解压缩选项
   * @param result 结果对象
   */
  private async performExtraction(
    archivePath: string,
    targetDir: string,
    options: ExtractionOptions,
    result: ExtractionResult
  ): Promise<void> {
    await this.performExtractionEnhanced(archivePath, targetDir, options, result);
  }

  private async performExtractionEnhanced(
    archivePath: string,
    targetDir: string,
    options: ExtractionOptions,
    result: ExtractionResult
  ): Promise<void> {
    const extension = this.getFileExtension(archivePath);

    try {
      if (this.zlibFormats.includes(extension)) {
        await this.extractZipArchive(archivePath, targetDir, options);
      } else if (
        this.commonsCompressFormats.includes(extension) ||
        this.unrarFormats.includes(extension) ||
        this.sevenZipFormats.includes(extension)
      ) {
        await this.extractWithOh7zip(archivePath, targetDir, options.password, extension);
      } else {
        throw new Error(`不支持的压缩格式: ${extension}`);
      }

      logger.debug(TAG, `解压完成: ${archivePath} -> ${targetDir}`);
    } catch (error) {
      const errorStr = String(error);
      logger.error(TAG, `解压失败: ${errorStr}`);

      if (this.isPasswordRequiredError(error)) {
        throw this.createPasswordRequiredError(archivePath);
      }

      if (errorStr.includes('900003') || errorStr.includes('not in ZIP format')) {
        throw new Error('压缩文件格式不正确或已损坏');
      } else if (errorStr.includes('13900002') || errorStr.includes('IO')) {
        throw new Error('解压过程中发生 IO 错误');
      }

      throw new Error(`解压失败: ${errorStr}`);
    }
  }
  
  /**
   * 使用系统zlib解压ZIP/CBZ格式
   */
  private async extractWithZlib(archivePath: string, targetDir: string): Promise<void> {
    logger.info(TAG, `使用系统zlib解压: ${archivePath}`);
    await zlib.decompressFile(archivePath, targetDir);
  }

  public isPasswordRequiredError(error: Error | BusinessError | Object | string | number | boolean | null | undefined): boolean {
    const errorStr = String(error).toLowerCase();
    return errorStr.includes('压缩包需要正确的密码') ||
      errorStr.includes('missing_password') ||
      errorStr.includes('wrong password') ||
      errorStr.includes('password required') ||
      errorStr.includes('encrypted') ||
      errorStr.includes('密码错误') ||
      errorStr.includes('需要密码') ||
      errorStr.includes('密码') && errorStr.includes('正确');
  }

  private createPasswordRequiredError(archivePath: string): Error {
    const fileName = this.getFileNameFromUri(archivePath);
    return new Error(`压缩包需要正确的密码后才能继续导入: ${fileName}`);
  }

  private async extractZipArchive(
    archivePath: string,
    targetDir: string,
    options: ExtractionOptions
  ): Promise<void> {
    const finalPassword = options.password?.trim();
    if (!finalPassword) {
      try {
        await this.extractWithZlib(archivePath, targetDir);
        return;
      } catch (error) {
        logger.warn(TAG, `zlib 解压失败，尝试使用 minizip 兜底: ${archivePath}`, String(error));
        // zlib 可能已经写入了部分条目。回退前必须清空目标目录，避免
        // 编码错误的半成品与 minizip 的正确结果混合，造成重复页面。
        try {
          await this.sandboxManager.deleteDirectory(targetDir, true);
          await this.sandboxManager.createDirectory(targetDir);
        } catch (cleanupError) {
          throw new Error(`清理 zlib 半成品失败，无法安全回退: ${String(cleanupError)}`);
        }
      }
    }

    await this.extractZipWithMinizip(
      archivePath,
      targetDir,
      finalPassword,
      options.maxFiles,
      options.maxTotalSize
    );
  }

  private async extractZipWithMinizip(
    archivePath: string,
    targetDir: string,
    password?: string,
    maxFiles?: number,
    maxTotalSize?: number
  ): Promise<void> {
    const charEncoding = this.pickZipCharEncoding(archivePath);
    const minizip = this.createMinizipReader(archivePath, charEncoding);
    const entryNames = minizip.GetEntryNames();
    const finalPassword = password || '';

    if (!finalPassword && this.zipHasEncryptedEntries(minizip, entryNames)) {
      throw this.createPasswordRequiredError(archivePath);
    }

    let archiveFileCount: number = 0;
    for (const entryName of entryNames) {
      if (!entryName.endsWith('/')) {
        archiveFileCount += 1;
      }
    }
    if (maxFiles !== undefined && archiveFileCount > maxFiles) {
      throw new Error(`ZIP 条目数量超过限制: ${archiveFileCount}/${maxFiles}`);
    }

    let extractedTotalSize: number = 0;

    for (const entryName of entryNames) {
      const isDirectoryEntry = entryName.endsWith('/');
      const safeEntryPath = this.normalizeArchiveEntryPath(entryName);
      if (!safeEntryPath) {
        continue;
      }

      const outputPath = `${targetDir}/${safeEntryPath}`;
      if (isDirectoryEntry) {
        await this.sandboxManager.createDirectory(outputPath);
        continue;
      }

      const parentDir = outputPath.substring(0, outputPath.lastIndexOf('/'));
      if (parentDir.length > 0) {
        await this.sandboxManager.createDirectory(parentDir);
      }

      const content = minizip.ExtractFileToJS(entryName, finalPassword);
      if (content === undefined) {
        if (minizip.IsEncrypto(entryName)) {
          throw this.createPasswordRequiredError(archivePath);
        }
        throw new Error(`ZIP 条目解压失败: ${entryName}`);
      }

      extractedTotalSize += content.byteLength;
      if (maxTotalSize !== undefined && extractedTotalSize > maxTotalSize) {
        throw new Error(`ZIP 解压总大小超过限制: ${extractedTotalSize}/${maxTotalSize}`);
      }

      const file = SafeFileUtils.openSync(outputPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      try {
        SafeFileUtils.writeSync(file.fd, content);
      } finally {
        SafeFileUtils.closeSync(file);
      }
    }
  }

  private createMinizipReader(archivePath: string, charEncoding?: number): MinizipNative {
    const minizip = new MinizipNative(archivePath);
    if (charEncoding !== undefined) {
      minizip.SetCharEncoding(charEncoding);
    }

    const openCode = minizip.Open();
    if (openCode !== 0) {
      throw new Error(`打开 ZIP 文件失败: code=${openCode}`);
    }

    return minizip;
  }

  private zipHasEncryptedEntries(minizip: MinizipNative, entryNames: string[]): boolean {
    for (const entryName of entryNames) {
      if (!entryName.endsWith('/') && minizip.IsEncrypto(entryName)) {
        return true;
      }
    }
    return false;
  }

  private pickZipCharEncoding(archivePath: string): number | undefined {
    let bestEncoding: number | undefined = undefined;
    let bestScore = Number.MIN_SAFE_INTEGER;

    for (const encoding of this.zipEncodingCandidates) {
      try {
        const minizip = this.createMinizipReader(archivePath, encoding);
        const score = this.scoreArchiveEntryNames(minizip.GetEntryNames());
        if (score > bestScore) {
          bestScore = score;
          bestEncoding = encoding;
        }
      } catch (_error) {
        continue;
      }
    }

    return bestEncoding;
  }

  private scoreArchiveEntryNames(entryNames: string[]): number {
    let score = 0;
    for (const entryName of entryNames) {
      score += entryName.length;
      for (let i = 0; i < entryName.length; i++) {
        const char = entryName.charAt(i);
        if (char === '\uFFFD' || char === '?') {
          score -= 10;
        } else if (char === '锟') {
          score -= 20;
        } else if (/[A-Za-z0-9/_\\.()\[\]\u4e00-\u9fa5-]/.test(char)) {
          score += 2;
        }
      }
    }
    return score;
  }

  private normalizeArchiveEntryPath(entryName: string): string {
    const normalized = entryName.replace(/\\/g, '/').replace(/^\/+/, '');
    const parts = normalized.split('/');
    const safeParts: string[] = [];

    for (const part of parts) {
      if (!part || part === '.') {
        continue;
      }
      if (part === '..') {
        throw new Error(`压缩包包含非法路径: ${entryName}`);
      }
      safeParts.push(part);
    }

    return safeParts.join('/');
  }

  private async extractWithOh7zip(
    archivePath: string,
    targetDir: string,
    password?: string,
    extension?: string
  ): Promise<void> {
    const uncompress = new Uncompress();
    const config: Config7z = {
      src: archivePath,
      dst: targetDir
    };

    const finalPassword = password?.trim();
    if (finalPassword) {
      config.pwd = finalPassword;
    }

    const code = await uncompress.extractAsync(config);
    if (code !== 0) {
      if (code === 10) {
        throw this.createPasswordRequiredError(archivePath);
      }
      throw new Error(`7z 解压失败: code=${code}`);
    }

    // 适配 tar.gz/tgz 解压出的 .tar 文件二次解压
    if (extension === '.gz' || extension === '.tgz') {
      try {
        const files = await this.sandboxManager.listDirectory(targetDir);
        // 如果解压出来正好只有一个文件且是以 .tar 结尾，执行二次解压
        if (files.length === 1 && files[0].toLowerCase().endsWith('.tar')) {
          const tarPath = `${targetDir}/${files[0]}`;
          logger.info(TAG, `检测到 tar 包，执行二次解压: ${tarPath}`);
          const tarConfig: Config7z = {
            src: tarPath,
            dst: targetDir
          };
          const tarCode = await uncompress.extractAsync(tarConfig);
          if (tarCode === 0) {
            // 解压成功后删除临时 .tar 文件
            await this.sandboxManager.deleteFile(tarPath);
            logger.debug(TAG, `清理临时 tar 文件: ${tarPath}`);
          } else {
            logger.warn(TAG, `二次解压 tar 文件失败: code=${tarCode}`);
          }
        }
      } catch (err) {
        logger.warn(TAG, `检查 tar 二次解压失败`, String(err));
      }
    }
  }
  
  /**
   * 从路径获取文件名
   */
  private getFileNameFromPath(filePath: string): string {
    const lastSlash = filePath.lastIndexOf('/');
    return lastSlash >= 0 ? filePath.substring(lastSlash + 1) : filePath;
  }

  /**
   * 扫描解压缩后的文件
   * @param directory 目录路径
   * @param options 解压缩选项
   * @returns 文件信息列表
   */
  private async scanExtractedFiles(
    directory: string,
    options: ExtractionOptions
  ): Promise<ExtractedFileInfo[]> {
    const fileInfos: ExtractedFileInfo[] = [];
    const state: ExtractionScanState = { totalSize: 0 };

    try {
      await this.scanExtractedDirectory(directory, options, fileInfos, state);

    } catch (error) {
      const errorStr = String(error);
      logger.error(TAG, '扫描解压缩文件失败', errorStr);
      throw error as Error;
    }

    return fileInfos;
  }

  private async scanExtractedDirectory(
    directory: string,
    options: ExtractionOptions,
    fileInfos: ExtractedFileInfo[],
    state: ExtractionScanState
  ): Promise<void> {
    const files: string[] = await this.sandboxManager.listDirectory(directory);
    files.sort((left: string, right: string): number => this.naturalCompare(left, right));
    for (const fileName of files) {
      const filePath: string = `${directory}/${fileName}`;
      if (await this.sandboxManager.isSymbolicLink(filePath)) {
        logger.warn(TAG, `扫描解压结果跳过符号链接: ${filePath}`);
        continue;
      }

      const stat = await fileIo.lstat(filePath);
      if (stat.isDirectory()) {
        await this.scanExtractedDirectory(directory + '/' + fileName, options, fileInfos, state);
        continue;
      }

      if (options.fileFilter && !options.fileFilter(fileName)) {
        continue;
      }
      if (options.maxFiles !== undefined && fileInfos.length >= options.maxFiles) {
        throw new Error(`达到最大文件数量限制: ${options.maxFiles}`);
      }
      if (options.maxTotalSize !== undefined && state.totalSize + stat.size > options.maxTotalSize) {
        throw new Error(`达到最大总大小限制: ${options.maxTotalSize} 字节`);
      }

      const mimeType: string = getMimeTypeFromExtension(this.getFileExtension(fileName).substring(1));
      const extractedFileInfo: ExtractedFileInfo = {
        fileName: fileName,
        filePath: filePath,
        fileSize: stat.size,
        mimeType: mimeType,
        isImage: this.supportedImageFormats.includes(mimeType),
        isXml: fileName.toLowerCase().endsWith('.xml')
      };
      fileInfos.push(extractedFileInfo);
      state.totalSize += stat.size;
    }
  }

  /**
   * 查找ComicInfo.xml文件（支持递归搜索多层目录）
   * @param directory 目录路径
   * @param maxDepth 最大递归深度，默认5层
   * @returns ComicInfo.xml文件路径，如果未找到则返回null
   */
  private async findComicInfoFile(directory: string, maxDepth: number = 5): Promise<string | null> {
    return await this.findComicInfoFileRecursive(directory, 0, maxDepth);
  }

  /**
   * 递归查找ComicInfo.xml文件
   * @param directory 当前目录路径
   * @param currentDepth 当前递归深度
   * @param maxDepth 最大递归深度
   * @returns ComicInfo.xml文件路径，如果未找到则返回null
   */
  private async findComicInfoFileRecursive(
    directory: string, 
    currentDepth: number, 
    maxDepth: number
  ): Promise<string | null> {
    try {
      if (currentDepth > maxDepth) {
        logger.warn(TAG, `达到最大递归深度 ${maxDepth}，停止搜索`);
        return null;
      }

      const files = await this.sandboxManager.listDirectory(directory);
      
      // 首先在当前目录查找ComicInfo.xml
      for (const fileName of files) {
        if (fileName.toLowerCase() === 'comicinfo.xml') {
          const filePath = `${directory}/${fileName}`;
          if (await this.sandboxManager.isSymbolicLink(filePath)) {
            continue;
          }
          logger.info(TAG, `找到ComicInfo.xml: ${filePath}`);
          return filePath;
        }
      }

      // 如果当前目录没有，递归查找子目录
      for (const fileName of files) {
        const filePath = `${directory}/${fileName}`;
        if (await this.sandboxManager.isSymbolicLink(filePath)) {
          continue;
        }
        
        try {
          // 判断是否为目录（通过尝试列出目录内容）
          const isDirectory = await this.isDirectory(filePath);
          
          if (isDirectory) {
            const result = await this.findComicInfoFileRecursive(filePath, currentDepth + 1, maxDepth);
            if (result) {
              return result;
            }
          }
        } catch (error) {
          // 忽略无法访问的文件/目录
          continue;
        }
      }

      return null;
    } catch (error) {
      const errorStr = String(error);
      logger.error(TAG, `递归查找ComicInfo.xml失败: ${directory}`, errorStr);
      return null;
    }
  }

  /**
   * Return a ComicInfo.xml that is directly inside the supplied directory.
   * This deliberately does not recurse into sibling/child directories.
   */
  private async findDirectComicInfoFile(directory: string): Promise<string | null> {
    try {
      const files: string[] = await this.sandboxManager.listDirectory(directory);
      for (const fileName of files) {
        if (fileName.toLowerCase() === 'comicinfo.xml') {
          const filePath: string = `${directory}/${fileName}`;
          if (!(await this.sandboxManager.isSymbolicLink(filePath))) {
            return filePath;
          }
        }
      }
    } catch (error) {
      logger.debug(TAG, `Unable to read ComicInfo.xml directory: ${directory}`, String(error));
    }
    return null;
  }

  /**
   * Find the nearest metadata file on the direct parent chain of a flat image
   * directory. A bounded parent walk avoids taking metadata from an unrelated
   * sibling manga through the old recursive search.
   */
  private async findNearestParentComicInfoFile(
    directory: string,
    maxDepth: number = 4
  ): Promise<string | null> {
    let currentPath: string = this.convertUriToLocalPath(directory)
      .replace(/\\/g, '/').replace(/\/+$/g, '');
    for (let depth = 0; depth < maxDepth; depth++) {
      const slashIndex: number = currentPath.lastIndexOf('/');
      if (slashIndex < 0) {
        break;
      }
      if (slashIndex === 0) {
        currentPath = '/';
      } else {
        currentPath = currentPath.substring(0, slashIndex);
      }
      if (currentPath === '/') {
        break;
      }
      const comicInfoPath: string | null = await this.findDirectComicInfoFile(currentPath);
      if (comicInfoPath !== null) {
        return comicInfoPath;
      }
    }
    return null;
  }

  /**
   * 判断路径是否为目录
   * @param path 路径
   * @returns 是否为目录
   */
  private async isDirectory(path: string): Promise<boolean> {
    try {
      // 使用 lstat，符号链接不能作为可递归的导入目录。
      const stat = await fileIo.lstat(path);
      if (stat.isSymbolicLink()) {
        return false;
      }
      return stat.isDirectory();
    } catch (error) {
      return false;
    }
  }

  /**
   * 获取文件扩展名
   * @param filePath 文件路径
   * @returns 文件扩展名（包含点号）
   */
  private getFileExtension(filePath: string): string {
    const lastDot = filePath.lastIndexOf('.');
    return lastDot > 0 ? filePath.substring(lastDot).toLowerCase() : '';
  }

  /**
   * 获取不含扩展名的文件名
   * @param filePath 文件路径
   * @returns 不含扩展名的文件名
   */
  private getFileNameWithoutExtension(filePath: string): string {
    const fileName = filePath.substring(filePath.lastIndexOf('/') + 1);
    const lastDot = fileName.lastIndexOf('.');
    return lastDot > 0 ? fileName.substring(0, lastDot) : fileName;
  }


  /**
   * 清理解压缩目录
   * @param directory 要清理的目录路径
   */
  public async cleanupExtractionDirectory(directory: string): Promise<void> {
    try {
      if (await this.sandboxManager.exists(directory)) {
        await this.sandboxManager.deleteDirectory(directory, true);
        logger.debug(TAG, `清理解压缩目录: ${directory}`);
      }
    } catch (error) {
      const errorStr = String(error);
      logger.warn(TAG, `清理解压缩目录失败: ${directory}`, errorStr);
    }
  }

  /**
   * 检查是否为支持的压缩文件
   * @param filePath 文件路径
   * @returns 是否支持
   */
  public isSupportedArchive(filePath: string): boolean {
    // 转换URI路径为本地路径
    const localPath = this.convertUriToLocalPath(filePath);
    const extension = this.getFileExtension(localPath);
    return this.supportedArchiveFormats.includes(extension);
  }

  /**
   * 递归解压并查找ComicInfo.xml（支持嵌套压缩包和多层文件夹）
   * @param archivePath 压缩文件路径
   * @param maxRecursionDepth 最大递归深度，默认3层
   * @returns 递归解压结果
   */
  public async extractRecursivelyAndFindComicInfo(
    archivePath: string,
    maxRecursionDepth: number = 3,
    options?: Partial<ExtractionOptions>
  ): Promise<RecursiveExtractionResult> {
    const tempDirectories: string[] = [];
    const warnings: string[] = [];
    let totalFiles = 0;

    try {
      logger.info(TAG, `开始递归解压: ${archivePath}, 最大深度: ${maxRecursionDepth}`);
      
      const result = await this.extractRecursivelyInternal(
        archivePath,
        0,
        maxRecursionDepth,
        tempDirectories,
        warnings,
        options
      );

      totalFiles = result.totalFiles;

      // 查找最底层的有效目录（包含图片文件的目录）
      const finalPath = await this.findDeepestValidDirectory(result.extractedPath);
      
      // 在最底层目录查找ComicInfo.xml
      const comicInfoPath = await this.findComicInfoFile(finalPath);
      let comicInfoContent: string | undefined;
      let foundXml = false;

      if (comicInfoPath) {
        try {
          comicInfoContent = await this.sandboxManager.readTextFile(comicInfoPath);
          foundXml = true;
          logger.info(TAG, `找到ComicInfo.xml: ${comicInfoPath}`);
        } catch (error) {
          warnings.push(`读取ComicInfo.xml失败: ${error}`);
          logger.warn(TAG, '读取ComicInfo.xml失败', String(error));
        }
      } else {
        warnings.push('未找到ComicInfo.xml文件');
        logger.warn(TAG, '未找到ComicInfo.xml文件');
      }

      return {
        finalPath: finalPath,
        foundXml: foundXml,
        comicInfoContent: comicInfoContent,
        totalFiles: totalFiles,
        recursionDepth: result.recursionDepth,
        tempDirectories: tempDirectories,
        warnings: warnings
      };

    } catch (error) {
      logger.error(TAG, '递归解压失败', String(error));
      
      // 清理所有临时目录
      await this.cleanupTempDirectories(tempDirectories);
      
      throw error as Error;
    }
  }

  /**
   * 递归解压内部实现
   * @param path 当前路径（文件或目录）
   * @param currentDepth 当前递归深度
   * @param maxDepth 最大递归深度
   * @param tempDirectories 临时目录列表
   * @param warnings 警告信息列表
   * @returns 解压结果
   */
  private async extractRecursivelyInternal(
    path: string,
    currentDepth: number,
    maxDepth: number,
    tempDirectories: string[],
    warnings: string[],
    options?: Partial<ExtractionOptions>
  ): Promise<RecursiveExtractionInternalResult> {
    if (currentDepth > maxDepth) {
      logger.warn(TAG, `达到最大递归深度 ${maxDepth}`);
      warnings.push(`达到最大递归深度 ${maxDepth}，停止解压`);
      const maxDepthResult: RecursiveExtractionInternalResult = {
        extractedPath: path,
        totalFiles: 0,
        recursionDepth: currentDepth
      };
      return maxDepthResult;
    }

    // 如果是压缩文件，解压它
    if (this.isSupportedArchive(path)) {
      logger.info(TAG, `解压层级 ${currentDepth}: ${path}`);
      
      const extractResult = await this.extractArchive(path, options);
      
      if (!extractResult.success) {
        throw new Error(`解压失败: ${extractResult.error}`);
      }

      tempDirectories.push(extractResult.extractedPath);
      let totalFiles = extractResult.fileCount;
      let maxRecursionDepth = currentDepth;

      // 扫描解压后的内容
      const files = await this.sandboxManager.listDirectory(extractResult.extractedPath);
      
      // 检查是否有嵌套的压缩包
      const nestedArchives: string[] = [];
      for (const fileName of files) {
        const filePath = `${extractResult.extractedPath}/${fileName}`;
        if (this.isSupportedArchive(filePath)) {
          nestedArchives.push(filePath);
        }
      }

      // 如果有嵌套压缩包，继续递归解压
      if (nestedArchives.length > 0) {
        logger.info(TAG, `发现 ${nestedArchives.length} 个嵌套压缩包，继续递归解压`);
        
        // 处理第一个嵌套压缩包（通常每层只有一个压缩包）
        const nestedResult = await this.extractRecursivelyInternal(
          nestedArchives[0],
          currentDepth + 1,
          maxDepth,
          tempDirectories,
          warnings,
          options
        );
        
        totalFiles += nestedResult.totalFiles;
        maxRecursionDepth = Math.max(maxRecursionDepth, nestedResult.recursionDepth);
        
        const nestedFinalResult: RecursiveExtractionInternalResult = {
          extractedPath: nestedResult.extractedPath,
          totalFiles: totalFiles,
          recursionDepth: maxRecursionDepth
        };
        return nestedFinalResult;
      }

      const extractFinalResult: RecursiveExtractionInternalResult = {
        extractedPath: extractResult.extractedPath,
        totalFiles: totalFiles,
        recursionDepth: currentDepth
      };
      return extractFinalResult;
    }

    // 如果不是压缩文件，假设是目录，直接返回
    const directoryResult: RecursiveExtractionInternalResult = {
      extractedPath: path,
      totalFiles: 0,
      recursionDepth: currentDepth
    };
    return directoryResult;
  }

  /**
   * 查找最深的有效目录（包含图片文件的目录）
   * @param startPath 起始路径
   * @returns 最深的有效目录路径
   */
  private async findDeepestValidDirectory(startPath: string): Promise<string> {
    try {
      const files = await this.sandboxManager.listDirectory(startPath);
      
      // 检查当前目录是否包含图片文件
      const hasImages = await this.hasImageFiles(startPath);
      
      // 如果当前目录有图片，返回当前目录
      if (hasImages) {
        logger.info(TAG, `找到有效目录（包含图片）: ${startPath}`);
        return startPath;
      }

      // 如果当前目录只有一个子目录，递归进入
      if (files.length === 1) {
        const singleItem = `${startPath}/${files[0]}`;
        if (await this.sandboxManager.isSymbolicLink(singleItem)) {
          return startPath;
        }
        const isDir = await this.isDirectory(singleItem);
        
        if (isDir) {
          logger.debug(TAG, `进入单一子目录: ${singleItem}`);
          return await this.findDeepestValidDirectory(singleItem);
        }
      }

      // 查找所有子目录
      const subDirs: string[] = [];
      for (const fileName of files) {
        const filePath = `${startPath}/${fileName}`;
        if (await this.sandboxManager.isSymbolicLink(filePath)) {
          continue;
        }
        const isDir = await this.isDirectory(filePath);
        
        if (isDir) {
          subDirs.push(filePath);
        }
      }

      // 递归检查子目录，找到第一个包含图片的目录
      for (const subDir of subDirs) {
        const hasImagesInSub = await this.hasImageFiles(subDir);
        if (hasImagesInSub) {
          logger.info(TAG, `在子目录中找到有效目录: ${subDir}`);
          return await this.findDeepestValidDirectory(subDir);
        }
      }

      // 如果都没有图片，返回当前目录
      logger.info(TAG, `使用当前目录作为有效目录: ${startPath}`);
      return startPath;

    } catch (error) {
      logger.error(TAG, `查找有效目录失败: ${startPath}`, String(error));
      return startPath;
    }
  }

  /**
   * 检查目录是否包含图片文件
   * @param directory 目录路径
   * @returns 是否包含图片文件
   */
  private async hasImageFiles(directory: string): Promise<boolean> {
    try {
      const files = await this.sandboxManager.listDirectory(directory);
      
      for (const fileName of files) {
        const filePath: string = `${directory}/${fileName}`;
        if (await this.sandboxManager.isSymbolicLink(filePath)) {
          continue;
        }
        const extension = this.getFileExtension(fileName).toLowerCase();
        if (['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'].includes(extension)) {
          return true;
        }
      }
      
      return false;
    } catch (error) {
      logger.error(TAG, `检查图片文件失败: ${directory}`, String(error));
      return false;
    }
  }

  /**
   * 清理临时目录列表
   * @param tempDirectories 临时目录列表
   */
  private async cleanupTempDirectories(tempDirectories: string[]): Promise<void> {
    logger.info(TAG, `开始清理 ${tempDirectories.length} 个临时目录`);
    
    // Nested extraction targets can live inside their parent extraction root.
    // Remove children first so every tracked path is cleaned deterministically.
    for (let index = tempDirectories.length - 1; index >= 0; index--) {
      const dir: string = tempDirectories[index];
      try {
        await this.cleanupExtractionDirectory(dir);
      } catch (error) {
        logger.warn(TAG, `清理临时目录失败: ${dir}`, String(error));
      }
    }
  }

  /**
   * 清理递归解压结果（清理所有临时目录）
   * @param result 递归解压结果
   */
  public async cleanupRecursiveExtractionResult(result: RecursiveExtractionResult): Promise<void> {
    await this.cleanupTempDirectories(result.tempDirectories);
  }

  // ==================== 增强的压缩包结构解析 ====================

  /**
   * 解析压缩包结构（用于漫画导入）
   * 支持检测多层嵌套、多章节结构
   * @param archivePath 压缩包路径
   * @returns 解析后的结构信息
   */
  public async parseArchiveStructure(
    archivePath: string,
    options?: Partial<ExtractionOptions>
  ): Promise<ParsedArchiveStructure> {
    const tempDirectories: string[] = [];
    const warnings: string[] = [];
    const detectedChapters: DetectedChapterInfo[] = [];
    let hasComicInfo = false;
    let comicInfoContent: string | undefined;
    let totalImageCount = 0;
    let rootImageCount = 0;

    try {
      logger.info(TAG, `开始解析压缩包结构: ${archivePath}`);

      // 1. 递归解压所有嵌套的压缩包
      const extractResult = await this.extractAllNestedArchives(archivePath, tempDirectories, warnings, options);
      const extractedPath = extractResult.finalPath;

      // 2. 查找ComicInfo.xml
      const comicInfoPath = await this.findComicInfoFile(extractedPath);
      if (comicInfoPath) {
        try {
          comicInfoContent = SafeFileUtils.readTextSync(comicInfoPath);
          hasComicInfo = true;
          logger.info(TAG, `找到ComicInfo.xml: ${comicInfoPath}`);
        } catch (error) {
          warnings.push(`读取ComicInfo.xml失败: ${error}`);
        }
      }

      // 3. 扫描目录结构，检测章节
      const scanResult = await this.scanDirectoryForChapters(extractedPath);
      rootImageCount = scanResult.rootImageCount;
      totalImageCount = scanResult.totalImageCount;

      // 4. 处理检测到的章节
      for (const chapter of scanResult.chapters) {
        detectedChapters.push(chapter);
      }

      // 5. 如果没有检测到章节但有根目录图片，创建一个默认章节
      if (detectedChapters.length === 0 && rootImageCount > 0) {
        logger.info(TAG, `未检测到章节结构，根目录有 ${rootImageCount} 张图片`);
      }

      // 6. 对章节进行自然排序
      const rootChapterName: string = this.getFileNameWithoutExtension(
        this.getFileNameFromUri(archivePath)
      );
      this.appendRootImageChapter(detectedChapters, extractedPath, rootImageCount, rootChapterName);
      this.sortChaptersNaturally(detectedChapters);

      const result: ParsedArchiveStructure = {
        hasComicInfo: hasComicInfo,
        comicInfoContent: comicInfoContent,
        isMultiLayer: detectedChapters.length > 1 || extractResult.recursionDepth > 0,
        detectedChapters: detectedChapters,
        rootImageCount: rootImageCount,
        totalImageCount: totalImageCount,
        extractedPath: extractedPath,
        tempDirectories: tempDirectories,
        warnings: warnings
      };

      logger.info(TAG, `压缩包结构解析完成: ${detectedChapters.length} 个章节, ${totalImageCount} 张图片`);
      return result;

    } catch (error) {
      logger.error(TAG, '解析压缩包结构失败', String(error));
      
      // 清理临时目录
      await this.cleanupTempDirectories(tempDirectories);
      
      throw error as Error;
    }
  }

  private createNestedExtractionOptions(
    options: Partial<ExtractionOptions> | undefined,
    targetDirectory: string
  ): Partial<ExtractionOptions> {
    const nestedOptions: Partial<ExtractionOptions> = {
      targetDirectory: targetDirectory,
      overwrite: false,
      createSubDirectory: false,
      fileFilter: options?.fileFilter,
      maxFiles: options?.maxFiles,
      maxTotalSize: options?.maxTotalSize,
      password: options?.password
    };
    return nestedOptions;
  }

  private async findNestedArchiveFiles(
    directory: string,
    currentDepth: number = 0,
    maxDepth: number = 16
  ): Promise<string[]> {
    if (currentDepth > maxDepth) {
      throw new Error(`Nested archive directory depth exceeds ${maxDepth}: ${directory}`);
    }
    const nestedArchives: string[] = [];
    const entries: string[] = await this.sandboxManager.listDirectory(directory);
    entries.sort((left: string, right: string): number => this.naturalCompare(left, right));
    for (const entry of entries) {
      const entryPath: string = `${directory}/${entry}`;
      if (await this.sandboxManager.isSymbolicLink(entryPath)) {
        continue;
      }
      if (await this.isDirectory(entryPath)) {
        const childArchives: string[] = await this.findNestedArchiveFiles(
          entryPath,
          currentDepth + 1,
          maxDepth
        );
        for (const childArchive of childArchives) {
          nestedArchives.push(childArchive);
        }
      } else if (this.isSupportedArchive(entryPath)) {
        nestedArchives.push(entryPath);
      }
    }
    return nestedArchives;
  }

  /**
   * 递归解压所有嵌套的压缩包
   */
  private async extractAllNestedArchives(
    archivePath: string,
    tempDirectories: string[],
    warnings: string[],
    options?: Partial<ExtractionOptions>,
    maxDepth: number = 5,
    currentDepth: number = 0
  ): Promise<NestedExtractionResult> {
    if (currentDepth > maxDepth) {
      const depthError: string = `Nested archive depth exceeds ${maxDepth}: ${archivePath}`;
      warnings.push(depthError);
      throw new Error(depthError);
    }

    // 解压当前压缩包
    const extractResult = await this.extractArchive(archivePath, options);
    if (!extractResult.success) {
      throw new Error(`解压失败: ${extractResult.error}`);
    }

    tempDirectories.push(extractResult.extractedPath);
    let finalPath = extractResult.extractedPath;
    let maxRecursionDepth = currentDepth;

    // Scan all wrapper directories before creating nested extraction targets.
    const nestedArchives: string[] = await this.findNestedArchiveFiles(extractResult.extractedPath);

    // 递归解压所有嵌套的压缩包
    for (let nestedIndex = 0; nestedIndex < nestedArchives.length; nestedIndex++) {
      const nestedArchive: string = nestedArchives[nestedIndex];
      const archiveName: string = this.getFileNameWithoutExtension(nestedArchive);
      const safeArchiveName: string = archiveName.replace(/[\\/:*?"<>|]/g, '_') || 'archive';
      const nestedTargetDirectory: string =
        `${extractResult.extractedPath}/${safeArchiveName}__nested_${nestedIndex + 1}`;
      try {
        const nestedOptions: Partial<ExtractionOptions> = this.createNestedExtractionOptions(
          options,
          nestedTargetDirectory
        );
        const nestedResult = await this.extractAllNestedArchives(
          nestedArchive,
          tempDirectories,
          warnings,
          nestedOptions,
          maxDepth,
          currentDepth + 1
        );
        maxRecursionDepth = Math.max(maxRecursionDepth, nestedResult.recursionDepth);
      } catch (error) {
        const nestedError: string = `Failed to extract nested archive: ${nestedArchive}, ${error}`;
        warnings.push(nestedError);
        throw new Error(nestedError);
      }
    }

    // 如果只有一个子目录，进入该目录
    const updatedFiles = await this.sandboxManager.listDirectory(finalPath);
    if (updatedFiles.length === 1) {
      const singleItem = `${finalPath}/${updatedFiles[0]}`;
      const isDir = await this.isDirectory(singleItem);
      if (isDir) {
        finalPath = singleItem;
      }
    }

    const result: NestedExtractionResult = {
      finalPath: finalPath,
      recursionDepth: maxRecursionDepth
    };
    return result;
  }

  /**
   * Turn images that live directly in a parsed root into an explicit chapter.
   * The recursive scanner reports their count separately; without this step
   * mixed archives (root pages plus chapter directories) would silently omit
   * the root pages during import.
   */
  private appendRootImageChapter(
    chapters: DetectedChapterInfo[],
    rootPath: string,
    rootImageCount: number,
    displayName?: string
  ): void {
    if (rootImageCount <= 0) {
      return;
    }
    const fallbackName: string = this.getFileNameFromUri(rootPath) || 'Images';
    let rootName: string = fallbackName;
    if (displayName !== undefined && displayName.length > 0) {
      rootName = displayName;
    }
    const chapterName: string = chapters.length > 0 ? `${rootName} (Images)` : rootName;
    chapters.push(this.extractChapterInfoFromName(chapterName, rootPath, rootImageCount));
  }

  /**
   * 扫描目录结构，检测章节
   */
  private async scanDirectoryForChapters(rootPath: string): Promise<DirectoryScanResult> {
    const chapters: DetectedChapterInfo[] = [];
    let rootImageCount = 0;
    let totalImageCount = 0;

    try {
      const files = await this.sandboxManager.listDirectory(rootPath);

      for (const fileName of files) {
        const filePath = `${rootPath}/${fileName}`;
        if (await this.sandboxManager.isSymbolicLink(filePath)) {
          logger.warn(TAG, `跳过符号链接导入项: ${filePath}`);
          continue;
        }
        const isDir = await this.isDirectory(filePath);

        if (isDir) {
          // 递归检查子目录
          const subScanResult = await this.scanDirectoryForChapters(filePath);
          
          if (subScanResult.chapters.length > 0) {
            // 子目录里有嵌套的章节
            chapters.push(...subScanResult.chapters);
            totalImageCount += subScanResult.totalImageCount;
            
            // 如果这个子目录本身也包含散落的图片，把它们作为一个章节
            if (subScanResult.rootImageCount > 0) {
              const chapterInfo = this.extractChapterInfoFromName(fileName + " (Images)", filePath, subScanResult.rootImageCount);
              chapters.push(chapterInfo);
            }
          } else if (subScanResult.rootImageCount > 0) {
            // 子目录里没有更深层的章节，但有图片，它自己就是一个章节
            const chapterInfo = this.extractChapterInfoFromName(fileName, filePath, subScanResult.rootImageCount);
            chapters.push(chapterInfo);
            totalImageCount += subScanResult.rootImageCount;
          }
        } else {
          // 检查是否为图片文件
          const extension = this.getFileExtension(fileName).toLowerCase();
          if (['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.avif'].includes(extension)) {
            rootImageCount++;
            totalImageCount++;
          }
        }
      }

    } catch (error) {
      logger.error(TAG, `扫描目录失败: ${rootPath}`, String(error));
      throw error as Error;
    }

    const result: DirectoryScanResult = {
      chapters: chapters,
      rootImageCount: rootImageCount,
      totalImageCount: totalImageCount
    };
    return result;
  }

  /**
   * 统计目录中的图片数量
   */
  private async countImagesInDirectory(directory: string): Promise<number> {
    try {
      const files = await this.sandboxManager.listDirectory(directory);
      let count = 0;

      for (const fileName of files) {
        const filePath: string = `${directory}/${fileName}`;
        if (await this.sandboxManager.isSymbolicLink(filePath)) {
          continue;
        }
        const extension = this.getFileExtension(fileName).toLowerCase();
        if (['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.avif'].includes(extension)) {
          count++;
        }
      }

      return count;
    } catch (error) {
      logger.error(TAG, `统计图片数量失败: ${directory}`, String(error));
      return 0;
    }
  }

  /**
   * 从文件夹/文件名称提取章节信息
   */
  private extractChapterInfoFromName(name: string, path: string, pageCount: number): DetectedChapterInfo {
    // 尝试从名称中提取章节编号
    let chapterNumber = 0;
    let chapterTitle = name;

    // 常见的章节编号模式
    const patterns: RegExp[] = [
      /第(\d+)[话話章回卷]/,           // 第1话、第1章
      /[话話章回卷](\d+)/,              // 话1、章1
      /[Cc]h(?:apter)?[.\s]*(\d+)/i,   // Ch.1, Chapter 1
      /[Ee]p(?:isode)?[.\s]*(\d+)/i,   // Ep.1, Episode 1
      /[Vv]ol(?:ume)?[.\s]*(\d+)/i,    // Vol.1, Volume 1
      /[\[\(【（](\d+)[\]\)】）]/,      // [1], (1), 【1】
      /[_\-\s](\d{1,4})[_\-\s.]/,      // _001_, -01-
      /^(\d{1,4})$/,                    // 纯数字
      /(\d{1,4})$/                      // 末尾数字
    ];

    for (const pattern of patterns) {
      const match = name.match(pattern);
      if (match && match[1]) {
        const num = parseInt(match[1], 10);
        if (num > 0 && num < 10000) {
          chapterNumber = num;
          // 如果名称只是数字，生成标题
          if (/^\d+$/.test(name.trim())) {
            chapterTitle = `第${num}话`;
          }
          break;
        }
      }
    }

    const result: DetectedChapterInfo = {
      // 未命名章节先保留 0；自然排序完成后再用稳定的显示序号回填，
      // 避免多个 Prologue/Side Story 全部变成第 1 章。
      index: chapterNumber,
      number: chapterNumber,
      title: chapterTitle,
      originalName: name,
      path: path,
      pageCount: pageCount
    };
    return result;
  }

  /**
   * 对章节进行自然排序
   * 将外传章节放到最末尾，然后在外传部分内部按名称排序
   */
  private sortChaptersNaturally(chapters: DetectedChapterInfo[]): void {
    chapters.sort((a, b) => {
      const aIsExtra = this.isExtraChapter(a.title);
      const bIsExtra = this.isExtraChapter(b.title);
      
      // 如果一个是外传，一个不是，外传排在后面
      if (aIsExtra && !bIsExtra) return 1;
      if (!aIsExtra && bIsExtra) return -1;
      
      // 如果都是外传，按标题自然排序
      if (aIsExtra && bIsExtra) {
        return this.naturalCompare(a.title, b.title);
      }
      
      // 有明确编号的章节优先按编号；无法识别编号的章节按名称排在后面。
      const aHasNumber: boolean = a.number > 0;
      const bHasNumber: boolean = b.number > 0;
      if (aHasNumber && !bHasNumber) {
        return -1;
      }
      if (!aHasNumber && bHasNumber) {
        return 1;
      }
      if (aHasNumber && bHasNumber && a.number !== b.number) {
        return a.number - b.number;
      }
      // 如果编号相同，按原始名称自然排序
      return this.naturalCompare(a.originalName, b.originalName);
    });

    // 重新分配索引
    for (let i = 0; i < chapters.length; i++) {
      chapters[i].index = i + 1;
      if (chapters[i].number <= 0) {
        chapters[i].number = i + 1;
      }
    }
  }

  /**
   * 判断是否为外传章节
   * 支持多语言：外传、番外、特别篇、Extra、Side Story、Omake、Special等
   */
  private isExtraChapter(title: string): boolean {
    const extraKeywords = [
      '外传', '番外', '特别篇', '特典', '附录',
      'extra', 'side story', 'omake', 'special', 'bonus',
      'gaiden', 'bangai', 'tokubetsu'
    ];
    
    const lowerTitle = title.toLowerCase();
    return extraKeywords.some(keyword => lowerTitle.includes(keyword));
  }

  /**
   * 自然排序比较函数
   * 简化实现，避免复杂的类型问题
   */
  private naturalCompare(a: string, b: string): number {
    // 提取数字和非数字部分进行比较
    const extractParts = (str: string): Array<string | number> => {
      const parts: Array<string | number> = [];
      let current = '';
      let isDigit = false;
      
      for (let i = 0; i < str.length; i++) {
        const char = str[i];
        const charIsDigit = char >= '0' && char <= '9';
        
        if (i === 0) {
          isDigit = charIsDigit;
          current = char;
        } else if (charIsDigit === isDigit) {
          current += char;
        } else {
          if (isDigit) {
            parts.push(parseInt(current, 10));
          } else {
            parts.push(current);
          }
          current = char;
          isDigit = charIsDigit;
        }
      }
      
      if (current.length > 0) {
        if (isDigit) {
          parts.push(parseInt(current, 10));
        } else {
          parts.push(current);
        }
      }
      
      return parts;
    };
    
    const partsA = extractParts(a);
    const partsB = extractParts(b);
    
    const minLen = Math.min(partsA.length, partsB.length);
    for (let i = 0; i < minLen; i++) {
      const partA = partsA[i];
      const partB = partsB[i];
      
      const aIsNum = typeof partA === 'number';
      const bIsNum = typeof partB === 'number';
      
      if (aIsNum && bIsNum) {
        const diff = (partA as number) - (partB as number);
        if (diff !== 0) return diff;
      } else if (aIsNum) {
        return -1; // 数字排在字符串前面
      } else if (bIsNum) {
        return 1;
      } else {
        const cmp = (partA as string).localeCompare(partB as string);
        if (cmp !== 0) return cmp;
      }
    }
    
    return partsA.length - partsB.length;
  }

  /**
   * 解析文件夹结构（用于已解压的漫画文件夹导入）
   * 不做解压操作，直接扫描文件夹
   * @param folderPath 文件夹路径
   * @returns 解析后的结构信息（与parseArchiveStructure兼容）
   */
  public async parseFolderAsArchiveStructure(folderPath: string): Promise<ParsedArchiveStructure> {
    const warnings: string[] = [];
    const detectedChapters: DetectedChapterInfo[] = [];
    let hasComicInfo = false;
    let comicInfoContent: string | undefined;
    let totalImageCount = 0;
    let rootImageCount = 0;

    try {
      logger.info(TAG, `开始解析文件夹结构: ${folderPath}`);

      // 如果只有一个子目录，进入该目录
      let effectivePath = folderPath;
      const topFiles = await this.sandboxManager.listDirectory(folderPath);
      if (topFiles.length === 1) {
        const singleItem = `${folderPath}/${topFiles[0]}`;
        if (await this.isDirectory(singleItem)) {
          effectivePath = singleItem;
        }
      }

      // 1. 查找ComicInfo.xml
      const comicInfoPath = await this.findComicInfoFile(effectivePath);
      if (comicInfoPath) {
        try {
          comicInfoContent = SafeFileUtils.readTextSync(comicInfoPath);
          hasComicInfo = true;
          logger.info(TAG, `找到ComicInfo.xml: ${comicInfoPath}`);
        } catch (error) {
          warnings.push(`读取ComicInfo.xml失败: ${error}`);
        }
      }

      // 2. 扫描目录结构，检测章节
      const scanResult = await this.scanDirectoryForChapters(effectivePath);
      rootImageCount = scanResult.rootImageCount;
      totalImageCount = scanResult.totalImageCount;

      // 3. 处理检测到的章节
      for (const chapter of scanResult.chapters) {
        detectedChapters.push(chapter);
      }

      // 4. 对章节进行自然排序
      this.appendRootImageChapter(detectedChapters, effectivePath, rootImageCount);
      this.sortChaptersNaturally(detectedChapters);

      const result: ParsedArchiveStructure = {
        hasComicInfo: hasComicInfo,
        comicInfoContent: comicInfoContent,
        isMultiLayer: detectedChapters.length > 1,
        detectedChapters: detectedChapters,
        rootImageCount: rootImageCount,
        totalImageCount: totalImageCount,
        extractedPath: effectivePath,
        tempDirectories: [], // 文件夹不需要清理临时目录
        warnings: warnings
      };

      logger.info(TAG, `文件夹结构解析完成: ${detectedChapters.length} 个章节, ${totalImageCount} 张图片`);
      return result;

    } catch (error) {
      logger.error(TAG, '解析文件夹结构失败', String(error));
      throw error as Error;
    }
  }

  /**
   * 递归发现可导入的漫画候选。
   *
   * 一个目录可能同时包含多个 CBZ、多个散图目录以及 ComicInfo.xml。
   * 不能把整个目录直接当作一部漫画，否则不同 Series 的元数据会互相覆盖。
   * 这里把每个归档文件和“直属包含图片的目录”分别返回，调用方再逐项解析和分组。
   * 平铺散图目录使用 folder-flat: 前缀，避免旧的 folder: 语义把单章误判为多章节容器。
   */
  public async discoverMangaImportCandidates(
    folderPath: string,
    maxDepth: number = 16,
    maxCandidates: number = 2000,
    excludedDirectoryNames: string[] = []
  ): Promise<string[]> {
    const candidates: string[] = [];
    const visited: Set<string> = new Set<string>();
    await this.discoverMangaImportCandidatesRecursive(
      folderPath,
      0,
      maxDepth,
      maxCandidates,
      excludedDirectoryNames,
      visited,
      candidates
    );
    candidates.sort((left: string, right: string): number => {
      return this.naturalCompare(left, right);
    });
    return candidates;
  }

  private async discoverMangaImportCandidatesRecursive(
    directory: string,
    currentDepth: number,
    maxDepth: number,
    maxCandidates: number,
    excludedDirectoryNames: string[],
    visited: Set<string>,
    candidates: string[]
  ): Promise<void> {
    if (currentDepth > maxDepth || candidates.length >= maxCandidates) {
      return;
    }
    const normalizedDirectory: string = directory.replace(/\\/g, '/');
    if (visited.has(normalizedDirectory)) {
      return;
    }
    visited.add(normalizedDirectory);

    let entries: string[];
    try {
      entries = await this.sandboxManager.listDirectory(directory);
    } catch (error) {
      logger.warn(TAG, `发现漫画候选时无法读取目录: ${directory}`, String(error));
      return;
    }

    entries.sort((left: string, right: string): number => this.naturalCompare(left, right));
    const childDirectories: string[] = [];
    let directImageCount: number = 0;
    for (const entry of entries) {
      if (entry.startsWith('.')) {
        continue;
      }
      const entryPath: string = `${directory}/${entry}`;
      if (await this.sandboxManager.isSymbolicLink(entryPath)) {
        logger.warn(TAG, `发现漫画候选时跳过符号链接: ${entryPath}`);
        continue;
      }
      if (await this.isDirectory(entryPath)) {
        if (excludedDirectoryNames.includes(entry.toLowerCase())) {
          continue;
        }
        childDirectories.push(entryPath);
        continue;
      }
      if (this.isSupportedArchive(entryPath)) {
        if (candidates.length < maxCandidates) {
          candidates.push(entryPath);
        }
        continue;
      }
      const extension: string = this.getFileExtension(entry).toLowerCase();
      if (['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.avif'].includes(extension)) {
        directImageCount += 1;
      }
    }

    if (directImageCount > 0 && candidates.length < maxCandidates) {
      candidates.push(`folder-flat:${directory}`);
    }

    for (const childDirectory of childDirectories) {
      await this.discoverMangaImportCandidatesRecursive(
        childDirectory,
        currentDepth + 1,
        maxDepth,
        maxCandidates,
        excludedDirectoryNames,
        visited,
        candidates
      );
      if (candidates.length >= maxCandidates) {
        break;
      }
    }
  }

  /**
   * 解析只包含直属散图的目录，不递归读取子目录。
   * 这样每个 Gallery/章节目录只绑定自己的 ComicInfo.xml。
   */
  public async parseFlatImageFolderAsArchiveStructure(folderPath: string): Promise<ParsedArchiveStructure> {
    const warnings: string[] = [];
    let hasComicInfo: boolean = false;
    let comicInfoContent: string | undefined;
    let imageCount: number = 0;
    let directComicInfoFound: boolean = false;
    try {
      const entries: string[] = await this.sandboxManager.listDirectory(folderPath);
      for (const entry of entries) {
        const entryPath: string = `${folderPath}/${entry}`;
        if (await this.sandboxManager.isSymbolicLink(entryPath)) {
          logger.warn(TAG, `平铺散图解析跳过符号链接: ${entryPath}`);
          continue;
        }
        if (await this.isDirectory(entryPath)) {
          continue;
        }
        if (entry.toLowerCase() === 'comicinfo.xml') {
          directComicInfoFound = true;
          try {
            comicInfoContent = SafeFileUtils.readTextSync(entryPath);
            hasComicInfo = true;
          } catch (error) {
            warnings.push(`读取ComicInfo.xml失败: ${error}`);
          }
          continue;
        }
        const extension: string = this.getFileExtension(entry).toLowerCase();
        if (['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.avif'].includes(extension)) {
          imageCount += 1;
        }
      }
      if (!directComicInfoFound) {
        const parentComicInfoPath: string | null = await this.findNearestParentComicInfoFile(folderPath);
        if (parentComicInfoPath !== null) {
          try {
            comicInfoContent = SafeFileUtils.readTextSync(parentComicInfoPath);
            hasComicInfo = true;
            logger.info(TAG, `Flat image folder inherited ComicInfo.xml: ${parentComicInfoPath}`);
          } catch (error) {
            warnings.push(`读取父级ComicInfo.xml失败: ${error}`);
          }
        }
      }
      if (imageCount <= 0) {
        throw new Error(`目录中未找到图片: ${folderPath}`);
      }
      const detectedChapters: DetectedChapterInfo[] = [];
      this.appendRootImageChapter(detectedChapters, folderPath, imageCount);
      const result: ParsedArchiveStructure = {
        hasComicInfo: hasComicInfo,
        comicInfoContent: comicInfoContent,
        isMultiLayer: false,
        detectedChapters: detectedChapters,
        rootImageCount: imageCount,
        totalImageCount: imageCount,
        extractedPath: folderPath,
        tempDirectories: [],
        warnings: warnings
      };
      logger.info(TAG, `平铺散图目录解析完成: ${folderPath}, ${imageCount} 张图片`);
      return result;
    } catch (error) {
      logger.error(TAG, `解析平铺散图目录失败: ${folderPath}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 清理解析后的结构（清理临时目录）
   */
  public async cleanupParsedArchiveStructure(structure: ParsedArchiveStructure): Promise<void> {
    await this.cleanupTempDirectories(structure.tempDirectories);
  }
}

/**
 * 检测到的章节信息（内部使用）
 */
interface DetectedChapterInfo {
  index: number;
  number: number;
  title: string;
  originalName: string;
  path: string;
  pageCount: number;
}

/**
 * 嵌套解压结果（内部使用）
 */
interface NestedExtractionResult {
  finalPath: string;
  recursionDepth: number;
}

/**
 * 目录扫描结果（内部使用）
 */
interface DirectoryScanResult {
  chapters: DetectedChapterInfo[];
  rootImageCount: number;
  totalImageCount: number;
}

interface ExtractionScanState {
  totalSize: number;
}

/**
 * 解析后的压缩包结构（导出）
 */
export interface ParsedArchiveStructure {
  hasComicInfo: boolean;
  comicInfoContent?: string;
  isMultiLayer: boolean;
  detectedChapters: DetectedChapterInfo[];
  rootImageCount: number;
  totalImageCount: number;
  extractedPath: string;
  tempDirectories: string[];
  warnings: string[];
}
