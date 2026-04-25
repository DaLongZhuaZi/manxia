/**
 * Download目录管理器
 * 管理应用在系统Download文件夹中的专属目录
 * 使用DocumentViewPicker的DOWNLOAD模式获取访问权限
 */

import { picker, fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { logger } from '../../Utils/Logger';

const TAG = 'DownloadDirManager';

/**
 * Download目录信息
 */
export interface DownloadDirInfo {
  path: string;      // 文件系统路径
  uri: string;       // URI（用于后续访问）
  isInitialized: boolean;
}

/**
 * Download目录管理器单例
 */
export class DownloadDirManager {
  private static instance: DownloadDirManager;
  private context: common.UIAbilityContext | null = null;
  private downloadDirPath: string = '';
  private downloadDirUri: string = '';
  private isInitialized: boolean = false;
  private initPromise: Promise<boolean> | null = null;

  private constructor() {
    logger.info(TAG, 'Download目录管理器初始化');
  }

  public static getInstance(): DownloadDirManager {
    if (!DownloadDirManager.instance) {
      DownloadDirManager.instance = new DownloadDirManager();
    }
    return DownloadDirManager.instance;
  }

  /**
   * 设置应用上下文
   */
  public setContext(context: common.UIAbilityContext): void {
    this.context = context;
    logger.info(TAG, '应用上下文已设置');
  }

  /**
   * 获取Download目录信息
   */
  public getDirInfo(): DownloadDirInfo {
    return {
      path: this.downloadDirPath,
      uri: this.downloadDirUri,
      isInitialized: this.isInitialized
    };
  }

  /**
   * 检查是否已初始化
   */
  public isReady(): boolean {
    return this.isInitialized && this.downloadDirPath !== '';
  }

  /**
   * 获取Download目录路径
   */
  public getPath(): string {
    return this.downloadDirPath;
  }

  /**
   * 获取Download目录URI
   */
  public getUri(): string {
    return this.downloadDirUri;
  }

  /**
   * 设置Download目录信息（从外部设置，如DataManagementPage）
   */
  public setDirInfo(path: string, uri: string): void {
    this.downloadDirPath = path;
    this.downloadDirUri = uri;
    this.isInitialized = true;
    logger.info(TAG, `Download目录已设置: ${path}`);
  }

  /**
   * 请求用户授权并初始化Download目录
   * 返回Promise，成功返回true，失败返回false
   */
  public async requestAccess(): Promise<boolean> {
    // 如果已经初始化，直接返回
    if (this.isInitialized && this.downloadDirPath) {
      return true;
    }

    // 如果正在初始化，等待完成
    if (this.initPromise) {
      return this.initPromise;
    }

    // 开始初始化
    this.initPromise = this.doRequestAccess();
    const result = await this.initPromise;
    this.initPromise = null;
    return result;
  }

  /**
   * 执行实际的授权请求
   */
  private async doRequestAccess(): Promise<boolean> {
    try {
      if (!this.context) {
        logger.error(TAG, '应用上下文未设置');
        return false;
      }

      const documentViewPicker = new picker.DocumentViewPicker(this.context);
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;

      logger.info(TAG, '开始使用DOWNLOAD模式请求访问权限...');

      return new Promise<boolean>((resolve) => {
        documentViewPicker.save(documentSaveOptions).then((documentSaveResult: Array<string>) => {
          if (documentSaveResult.length > 0) {
            const uri = documentSaveResult[0];
            logger.info(TAG, `DOWNLOAD模式返回URI: ${uri}`);

            // 保存目录路径和URI
            const uriObj = new fileUri.FileUri(uri);
            this.downloadDirPath = uriObj.path;
            this.downloadDirUri = uri;
            this.isInitialized = true;

            // 创建初始化标记文件
            this.createInitFile();

            logger.info(TAG, `Download目录初始化成功: ${this.downloadDirPath}`);
            resolve(true);
          } else {
            logger.warn(TAG, 'DOWNLOAD模式未返回URI');
            resolve(false);
          }
        }).catch((err: Error) => {
          logger.error(TAG, `DOWNLOAD模式失败: ${err.message}`);
          resolve(false);
        });
      });
    } catch (error) {
      logger.error(TAG, `请求Download目录访问失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 创建初始化标记文件
   */
  private createInitFile(): void {
    try {
      const initFilePath = `${this.downloadDirPath}/.manxia_init`;
      const file = fs.openSync(initFilePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      fs.writeSync(file.fd, `漫匣应用目录初始化文件\n创建时间: ${new Date().toISOString()}`);
      fs.closeSync(file.fd);
      logger.info(TAG, `初始化文件已创建: ${initFilePath}`);
    } catch (error) {
      logger.warn(TAG, `创建初始化文件失败: ${String(error)}`);
    }
  }

  /**
   * 确保目录存在
   */
  public ensureDirectory(relativePath: string): string {
    if (!this.isInitialized || !this.downloadDirPath) {
      throw new Error('Download目录未初始化');
    }

    const fullPath = relativePath.startsWith(this.downloadDirPath)
      ? relativePath
      : `${this.downloadDirPath}/${relativePath}`;
    try {
      const stat = fs.statSync(fullPath);
      if (!stat.isDirectory()) {
        throw new Error('路径不是目录');
      }
    } catch (error) {
      // 目录不存在，创建它
      fs.mkdirSync(fullPath, true);
      logger.debug(TAG, `目录已创建: ${fullPath}`);
    }
    return fullPath;
  }

  /**
   * 获取漫画下载目录
   * 格式: Download/包名/manga/{mangaTitle}/{chapterTitle}/
   */
  public getMangaDownloadPath(mangaTitle: string, chapterTitle?: string): string {
    const sanitizedMangaTitle = this.sanitizeFolderName(mangaTitle);
    let path = `manga/${sanitizedMangaTitle}`;
    if (chapterTitle) {
      const sanitizedChapterTitle = this.sanitizeFolderName(chapterTitle);
      path = `${path}/${sanitizedChapterTitle}`;
    }
    return this.ensureDirectory(path);
  }

  /**
   * 获取在线漫画归档章节目录
   * 格式: Download/包名/manga/{sourceName}/{mangaTitle}/{chapterTitle}/
   */
  public getMangaArchiveDirectoryPath(sourceName: string, mangaTitle: string, chapterTitle: string): string {
    const sanitizedSourceName = this.sanitizeFolderName(sourceName.length > 0 ? sourceName : 'unknown_source');
    const sanitizedMangaTitle = this.sanitizeFolderName(mangaTitle.length > 0 ? mangaTitle : 'unknown_manga');
    const sanitizedChapterTitle = this.sanitizeFolderName(chapterTitle.length > 0 ? chapterTitle : 'unknown_chapter');
    const path = `manga/${sanitizedSourceName}/${sanitizedMangaTitle}/${sanitizedChapterTitle}`;
    return this.ensureDirectory(path);
  }

  /**
   * 获取在线漫画归档文件路径
   */
  public getMangaArchiveFilePath(sourceName: string, mangaTitle: string, chapterTitle: string): string {
    const chapterDir = this.getMangaArchiveDirectoryPath(sourceName, mangaTitle, chapterTitle);
    const fileName = `${this.sanitizeFolderName(chapterTitle.length > 0 ? chapterTitle : 'chapter')}.cbz`;
    return `${chapterDir}/${fileName}`;
  }

  /**
   * 获取图片保存路径
   */
  public getImageSavePath(mangaTitle: string, chapterTitle: string, pageIndex: number, extension: string = 'jpg'): string {
    const chapterPath = this.getMangaDownloadPath(mangaTitle, chapterTitle);
    return `${chapterPath}/page_${String(pageIndex + 1).padStart(4, '0')}.${extension}`;
  }

  /**
   * 清理文件夹名称，移除非法字符
   */
  private sanitizeFolderName(name: string): string {
    // 移除或替换文件系统不允许的字符
    return name
      .replace(/[\\/:*?"<>|]/g, '_')  // 替换非法字符
      .replace(/\s+/g, ' ')           // 合并多个空格
      .trim()                          // 去除首尾空格
      .substring(0, 100);              // 限制长度
  }

  /**
   * 检查文件是否存在
   */
  public fileExists(relativePath: string): boolean {
    if (!this.isInitialized || !this.downloadDirPath) {
      return false;
    }
    try {
      const fullPath = `${this.downloadDirPath}/${relativePath}`;
      fs.accessSync(fullPath);
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * 列出目录下的文件
   */
  public listFiles(relativePath: string = ''): string[] {
    if (!this.isInitialized || !this.downloadDirPath) {
      return [];
    }
    try {
      const fullPath = relativePath ? `${this.downloadDirPath}/${relativePath}` : this.downloadDirPath;
      return fs.listFileSync(fullPath);
    } catch (error) {
      logger.warn(TAG, `列出文件失败: ${String(error)}`);
      return [];
    }
  }

  /**
   * 删除文件
   */
  public deleteFile(relativePath: string): boolean {
    if (!this.isInitialized || !this.downloadDirPath) {
      return false;
    }
    try {
      const fullPath = `${this.downloadDirPath}/${relativePath}`;
      fs.unlinkSync(fullPath);
      logger.debug(TAG, `文件已删除: ${fullPath}`);
      return true;
    } catch (error) {
      logger.warn(TAG, `删除文件失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 删除目录（递归）
   */
  public deleteDirectory(relativePath: string): boolean {
    if (!this.isInitialized || !this.downloadDirPath) {
      return false;
    }
    try {
      const fullPath = `${this.downloadDirPath}/${relativePath}`;
      fs.rmdirSync(fullPath);
      logger.debug(TAG, `目录已删除: ${fullPath}`);
      return true;
    } catch (error) {
      logger.warn(TAG, `删除目录失败: ${String(error)}`);
      return false;
    }
  }
}

// 导出单例
export default DownloadDirManager.getInstance();
