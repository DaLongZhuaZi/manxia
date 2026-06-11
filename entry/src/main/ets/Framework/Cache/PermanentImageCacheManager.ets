import { SafeFileUtils } from '../../Utils/SafeFileUtils';
/**
 * 永久图片缓存管理器
 * 用于"边看边下载"功能，将图片永久保存到本地
 * 存储结构: /permanent_cache/source_{sourceId}/manga_{mangaId}/chapter_{chapterId}/page_{pageIndex}.jpg
 */

import { logger } from '../../Utils/Logger';
import { uiContextManager } from '../Managers/UIContextManager';
import fs from '@ohos.file.fs';
import http from '@ohos.net.http';
import { BusinessError } from '@ohos.base';
import { DataManager } from '../Data/DataManager';
import { MangaPage } from '../../Models/MangaModels';
import { DatabaseManager } from '../Database/DatabaseManager';

const TAG = 'PermanentImageCacheManager';

/**
 * 图源缓存配置
 */
export interface SourceCacheConfig {
  sourceId: number;
  downloadWhileReading: boolean;  // 是否开启边看边下载
  maxCacheSize: number;            // 最大缓存大小（字节），仅在未开启边看边下载时有效
}

/**
 * 漫画缓存统计
 */
export interface MangaCacheStats {
  sourceId: number;
  mangaId: string;
  mangaTitle: string;
  chapterCount: number;
  imageCount: number;
  totalSize: number;
  path: string;
}

/**
 * 文件信息接口
 */
interface FileInfo {
  path: string;
  mtime: number;
  size: number;
}

export class PermanentImageCacheManager {
  private static instance: PermanentImageCacheManager;
  private dbManager: DatabaseManager;
  private permanentCachePath: string = '';
  private tempCachePath: string = '';
  private pendingContextLogged: boolean = false;

  private constructor() {
    this.dbManager = DatabaseManager.getInstance();
    this.initCachePaths('constructor');
  }

  public static getInstance(): PermanentImageCacheManager {
    if (!PermanentImageCacheManager.instance) {
      PermanentImageCacheManager.instance = new PermanentImageCacheManager();
    }
    return PermanentImageCacheManager.instance;
  }

  /**
   * 初始化缓存路径
   */
  private initCachePaths(reason: string): boolean {
    try {
      const context = uiContextManager.getAbilityContext();
      if (!context) {
        if (!this.pendingContextLogged) {
          logger.debug(TAG, `Context未初始化，缓存路径等待后续按需初始化: reason=${reason}`);
          this.pendingContextLogged = true;
        }
        return false;
      }
      this.permanentCachePath = context.filesDir + '/permanent_cache';
      this.tempCachePath = context.cacheDir + '/temp_image_cache';
      this.pendingContextLogged = false;
      
      // 确保目录存在
      if (!SafeFileUtils.accessSync(this.permanentCachePath)) {
        SafeFileUtils.mkdirSync(this.permanentCachePath);
        logger.info(TAG, `创建永久缓存目录: ${this.permanentCachePath}`);
      }
      
      if (!SafeFileUtils.accessSync(this.tempCachePath)) {
        SafeFileUtils.mkdirSync(this.tempCachePath);
        logger.info(TAG, `创建临时缓存目录: ${this.tempCachePath}`);
      }
      return true;
    } catch (error) {
      logger.error(TAG, `初始化缓存路径失败: ${error}`);
      return false;
    }
  }

  private ensureCachePathsReady(reason: string): boolean {
    if (this.permanentCachePath.length > 0 && this.tempCachePath.length > 0) {
      return true;
    }
    return this.initCachePaths(reason);
  }

  /**
   * 获取图源缓存配置
   * [修复] 从user_settings表读取设置（与SourceSettingsPage保存位置一致）
   */
  async getSourceCacheConfig(sourceId: number): Promise<SourceCacheConfig> {
    try {
      const dataManager = DataManager.getInstance();
      
      // 从user_settings表读取设置
      const downloadWhileReadingRecord = await dataManager.getSourceUserSetting(sourceId, 'downloadWhileReading');
      const maxCacheSizeRecord = await dataManager.getSourceUserSetting(sourceId, 'maxCacheSize');
      
      return {
        sourceId: sourceId,
        downloadWhileReading: downloadWhileReadingRecord?.settingValue === '1' || downloadWhileReadingRecord?.settingValue === undefined,
        maxCacheSize: maxCacheSizeRecord?.settingValue ? Number(maxCacheSizeRecord.settingValue) * 1024 * 1024 : 1024 * 1024 * 1024 // 转换MB为字节，默认1GB
      };
    } catch (error) {
      logger.error(TAG, `获取图源缓存配置失败: ${error}`);
      return {
        sourceId: sourceId,
        downloadWhileReading: true,
        maxCacheSize: 1024 * 1024 * 1024
      };
    }
  }

  /**
   * 获取永久缓存路径
   */
  getPermanentImagePath(
    sourceId: number,
    mangaId: string,
    chapterId: string,
    pageIndex: number,
    imageUrl: string
  ): string {
    if (!this.ensureCachePathsReady('getPermanentImagePath')) {
      return '';
    }
    // 从URL提取扩展名
    let ext = '.jpg';
    const urlLower = imageUrl.toLowerCase();
    if (urlLower.includes('.png')) {
      ext = '.png';
    } else if (urlLower.includes('.webp')) {
      ext = '.webp';
    } else if (urlLower.includes('.jpeg')) {
      ext = '.jpeg';
    }
    
    const safeSourceId = sourceId.toString();
    const safeMangaId = mangaId.replace(/[^a-zA-Z0-9_-]/g, '_');
    const safeChapterId = chapterId.replace(/[^a-zA-Z0-9_-]/g, '_');
    
    return `${this.permanentCachePath}/source_${safeSourceId}/manga_${safeMangaId}/chapter_${safeChapterId}/page_${pageIndex}${ext}`;
  }

  /**
   * 获取临时缓存路径
   */
  getTempImagePath(
    sourceId: number,
    mangaId: string,
    chapterId: string,
    pageIndex: number,
    imageUrl: string
  ): string {
    if (!this.ensureCachePathsReady('getTempImagePath')) {
      return '';
    }
    let ext = '.jpg';
    const urlLower = imageUrl.toLowerCase();
    if (urlLower.includes('.png')) {
      ext = '.png';
    } else if (urlLower.includes('.webp')) {
      ext = '.webp';
    } else if (urlLower.includes('.jpeg')) {
      ext = '.jpeg';
    }
    
    const safeSourceId = sourceId.toString();
    const safeMangaId = mangaId.replace(/[^a-zA-Z0-9_-]/g, '_');
    const safeChapterId = chapterId.replace(/[^a-zA-Z0-9_-]/g, '_');
    
    return `${this.tempCachePath}/source_${safeSourceId}/manga_${safeMangaId}/chapter_${safeChapterId}/page_${pageIndex}${ext}`;
  }

  /**
   * 确保目录存在
   */
  private ensureDirectoryExists(filePath: string): void {
    const dirPath = filePath.substring(0, filePath.lastIndexOf('/'));
    if (!SafeFileUtils.accessSync(dirPath)) {
      // 递归创建目录
      const parts = dirPath.split('/');
      let currentPath = '';
      for (const part of parts) {
        if (part.length === 0) continue;
        currentPath += '/' + part;
        if (!SafeFileUtils.accessSync(currentPath)) {
          SafeFileUtils.mkdirSync(currentPath);
        }
      }
    }
  }

  /**
   * 保存图片到缓存
   */
  async saveImageToCache(
    sourceId: number,
    mangaId: string,
    chapterId: string,
    pageIndex: number,
    imageUrl: string,
    imageData: ArrayBuffer
  ): Promise<string | null> {
    try {
      if (!this.ensureCachePathsReady('saveImageToCache')) {
        logger.warn(TAG, '缓存路径尚未就绪，跳过本次图片缓存写入');
        return null;
      }
      const config = await this.getSourceCacheConfig(sourceId);
      
      // 根据配置决定保存到永久缓存还是临时缓存
      const targetPath = config.downloadWhileReading
        ? this.getPermanentImagePath(sourceId, mangaId, chapterId, pageIndex, imageUrl)
        : this.getTempImagePath(sourceId, mangaId, chapterId, pageIndex, imageUrl);
      if (targetPath.length <= 0) {
        return null;
      }
      
      // 如果文件已存在，直接返回
      if (SafeFileUtils.accessSync(targetPath)) {
        logger.debug(TAG, `图片已存在: ${targetPath}`);
        return targetPath;
      }
      
      // 确保目录存在
      this.ensureDirectoryExists(targetPath);
      
      // 写入文件
      await this.writeImageDataToFile(targetPath, imageData);
      
      logger.debug(TAG, `图片保存成功: ${targetPath}`);
      
      // 如果是临时缓存，检查是否超出限制
      if (!config.downloadWhileReading) {
        await this.checkAndCleanTempCache(sourceId, config.maxCacheSize);
      }
      
      return targetPath;
    } catch (error) {
      logger.error(TAG, `保存图片失败: ${error}`);
      return null;
    }
  }

  private async writeImageDataToFile(targetPath: string, imageData: ArrayBuffer): Promise<void> {
    let file: fs.File | null = null;
    let operationError: Error | null = null;
    try {
      file = await fs.open(targetPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      await fs.write(file.fd, imageData);
    } catch (error) {
      operationError = error as Error;
      throw operationError;
    } finally {
      if (file !== null) {
        try {
          await fs.close(file);
        } catch (closeError) {
          logger.warn(TAG, `关闭图片缓存文件句柄失败: ${targetPath}, ${String(closeError)}`);
          if (operationError === null) {
            throw closeError as Error;
          }
        }
      }
    }
  }

  /**
   * 检查并清理临时缓存
   */
  private async checkAndCleanTempCache(sourceId: number, maxSize: number): Promise<void> {
    try {
      const sourceTempPath = `${this.tempCachePath}/source_${sourceId}`;
      if (!SafeFileUtils.accessSync(sourceTempPath)) {
        return;
      }
      
      const currentSize = await this.calculateDirectorySize(sourceTempPath);
      
      if (currentSize > maxSize) {
        logger.info(TAG, `临时缓存超出限制: ${currentSize} > ${maxSize}，开始清理`);
        await this.cleanOldestTempCache(sourceTempPath, currentSize - maxSize);
      }
    } catch (error) {
      logger.error(TAG, `检查临时缓存失败: ${error}`);
    }
  }

  /**
   * 计算目录大小
   */
  private async calculateDirectorySize(dirPath: string): Promise<number> {
    let totalSize = 0;
    
    try {
      if (!SafeFileUtils.accessSync(dirPath)) {
        return 0;
      }
      
      const items = SafeFileUtils.listFileSync(dirPath);
      
      for (const item of items) {
        const itemPath = `${dirPath}/${item}`;
        const stat = SafeFileUtils.statSync(itemPath);
        
        if (stat.isDirectory()) {
          totalSize += await this.calculateDirectorySize(itemPath);
        } else {
          totalSize += stat.size;
        }
      }
    } catch (error) {
      logger.error(TAG, `计算目录大小失败: ${error}`);
    }
    
    return totalSize;
  }

  /**
   * 清理最旧的临时缓存
   */
  private async cleanOldestTempCache(dirPath: string, sizeToFree: number): Promise<void> {
    try {
      // 收集所有文件及其修改时间
      const files: Array<FileInfo> = [];
      await this.collectFiles(dirPath, files);
      
      // 按修改时间排序（最旧的在前）
      files.sort((a, b) => a.mtime - b.mtime);
      
      let freedSize = 0;
      for (const file of files) {
        if (freedSize >= sizeToFree) {
          break;
        }
        
        try {
          SafeFileUtils.unlinkSync(file.path);
          freedSize += file.size;
          logger.debug(TAG, `删除旧缓存: ${file.path}`);
        } catch (error) {
          logger.warn(TAG, `删除文件失败: ${file.path}`);
        }
      }
      
      logger.info(TAG, `清理完成: 释放${freedSize}字节`);
    } catch (error) {
      logger.error(TAG, `清理临时缓存失败: ${error}`);
    }
  }

  /**
   * 收集目录下所有文件
   */
  private async collectFiles(
    dirPath: string,
    files: Array<FileInfo>
  ): Promise<void> {
    try {
      if (!SafeFileUtils.accessSync(dirPath)) {
        return;
      }
      
      const items = SafeFileUtils.listFileSync(dirPath);
      
      for (const item of items) {
        const itemPath = `${dirPath}/${item}`;
        const stat = SafeFileUtils.statSync(itemPath);
        
        if (stat.isDirectory()) {
          await this.collectFiles(itemPath, files);
        } else {
          const fileInfo: FileInfo = {
            path: itemPath,
            mtime: stat.mtime,
            size: stat.size
          };
          files.push(fileInfo);
        }
      }
    } catch (error) {
      logger.error(TAG, `收集文件失败: ${error}`);
    }
  }

  /**
   * 获取所有图源的缓存配置
   * 扫描永久缓存目录，返回所有有缓存的图源配置
   */
  async getAllSourceConfigs(): Promise<SourceCacheConfig[]> {
    const configs: SourceCacheConfig[] = [];
    
    try {
      if (!this.ensureCachePathsReady('getAllSourceConfigs')) {
        return configs;
      }
      if (!SafeFileUtils.accessSync(this.permanentCachePath)) {
        return configs;
      }
      
      const items = SafeFileUtils.listFileSync(this.permanentCachePath);
      
      for (const item of items) {
        if (item.startsWith('source_')) {
          const sourceIdStr = item.replace('source_', '');
          const sourceId = parseInt(sourceIdStr, 10);
          
          if (!isNaN(sourceId)) {
            const config = await this.getSourceCacheConfig(sourceId);
            configs.push(config);
          }
        }
      }
      
      logger.info(TAG, `获取到 ${configs.length} 个图源配置`);
    } catch (error) {
      logger.error(TAG, `获取所有图源配置失败: ${error}`);
    }
    
    return configs;
  }
  
  /**
   * 获取图源的漫画缓存统计
   */
  async getSourceMangaCacheStats(sourceId: number): Promise<MangaCacheStats[]> {
    const stats: MangaCacheStats[] = [];
    
    try {
      if (!this.ensureCachePathsReady('getSourceMangaCacheStats')) {
        return stats;
      }
      const sourcePath = `${this.permanentCachePath}/source_${sourceId}`;
      if (!SafeFileUtils.accessSync(sourcePath)) {
        return stats;
      }
      
      const mangaDirs = SafeFileUtils.listFileSync(sourcePath);
      
      for (const mangaDir of mangaDirs) {
        if (mangaDir.startsWith('manga_')) {
          const mangaPath = `${sourcePath}/${mangaDir}`;
          const mangaId = mangaDir.replace('manga_', '');
          
          let chapterCount = 0;
          let imageCount = 0;
          let totalSize = 0;
          
          const chapterDirs = SafeFileUtils.listFileSync(mangaPath);
          chapterCount = chapterDirs.length;
          
          for (const chapterDir of chapterDirs) {
            const chapterPath = `${mangaPath}/${chapterDir}`;
            const images = SafeFileUtils.listFileSync(chapterPath);
            imageCount += images.length;
            
            for (const image of images) {
              const imagePath = `${chapterPath}/${image}`;
              const stat = SafeFileUtils.statSync(imagePath);
              totalSize += stat.size;
            }
          }
          
          stats.push({
            sourceId: sourceId,
            mangaId: mangaId,
            mangaTitle: mangaId, // 需要从数据库查询真实标题
            chapterCount: chapterCount,
            imageCount: imageCount,
            totalSize: totalSize,
            path: mangaPath
          });
        }
      }
    } catch (error) {
      logger.error(TAG, `获取漫画缓存统计失败: ${error}`);
    }
    
    return stats;
  }

  /**
   * 删除漫画缓存
   */
  async deleteMangaCache(sourceId: number, mangaId: string): Promise<boolean> {
    try {
      if (!this.ensureCachePathsReady('deleteMangaCache')) {
        return false;
      }
      const safeMangaId = mangaId.replace(/[^a-zA-Z0-9_-]/g, '_');
      const mangaPath = `${this.permanentCachePath}/source_${sourceId}/manga_${safeMangaId}`;
      
      if (SafeFileUtils.accessSync(mangaPath)) {
        await this.deleteDirectory(mangaPath);
        logger.info(TAG, `删除漫画缓存成功: ${mangaPath}`);
        return true;
      }
      
      return false;
    } catch (error) {
      logger.error(TAG, `删除漫画缓存失败: ${error}`);
      return false;
    }
  }

  /**
   * 递归删除目录
   */
  private async deleteDirectory(dirPath: string): Promise<void> {
    try {
      if (!SafeFileUtils.accessSync(dirPath)) {
        return;
      }
      
      const items = SafeFileUtils.listFileSync(dirPath);
      
      for (const item of items) {
        const itemPath = `${dirPath}/${item}`;
        const stat = SafeFileUtils.statSync(itemPath);
        
        if (stat.isDirectory()) {
          await this.deleteDirectory(itemPath);
        } else {
          SafeFileUtils.unlinkSync(itemPath);
        }
      }
      
      SafeFileUtils.rmdirSync(dirPath);
    } catch (error) {
      logger.error(TAG, `删除目录失败: ${dirPath}, ${error}`);
    }
  }

  /**
   * 获取缓存的图片路径（如果存在）
   */
  async getCachedImagePath(
    sourceId: number,
    mangaId: string,
    chapterId: string,
    pageIndex: number,
    imageUrl: string
  ): Promise<string | null> {
    try {
      if (!this.ensureCachePathsReady('getCachedImagePath')) {
        return null;
      }
      // 先检查永久缓存
      const permanentPath = this.getPermanentImagePath(sourceId, mangaId, chapterId, pageIndex, imageUrl);
      if (SafeFileUtils.accessSync(permanentPath)) {
        return permanentPath;
      }
      
      // 再检查临时缓存
      const tempPath = this.getTempImagePath(sourceId, mangaId, chapterId, pageIndex, imageUrl);
      if (SafeFileUtils.accessSync(tempPath)) {
        return tempPath;
      }
      
      return null;
    } catch (error) {
      return null;
    }
  }

  /**
   * 清理指定漫画的缓存
   */
  async cleanMangaCache(sourceId: number, mangaId: string): Promise<void> {
    try {
      if (!this.ensureCachePathsReady('cleanMangaCache')) {
        return;
      }
      const safeMangaId = mangaId.replace(/[^a-zA-Z0-9_-]/g, '_');
      const mangaPath = `${this.permanentCachePath}/source_${sourceId}/manga_${safeMangaId}`;
      
      if (SafeFileUtils.accessSync(mangaPath)) {
        this.deleteDirectory(mangaPath);
        logger.info(TAG, `已删除漫画缓存: ${mangaPath}`);
      }
    } catch (error) {
      const errorMsg = `删除漫画缓存失败: ${error}`;
      logger.error(TAG, errorMsg);
      throw new Error(errorMsg);
    }
  }
}
