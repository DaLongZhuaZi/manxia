/**
 * Suwayomi 图片缓存管理器
 * 将 Suwayomi 服务器上的漫画图片缓存到本地 Download/com.dlzz.manxia/suwayomi 目录
 * 支持：漫画封面、图源图标、章节页面
 */

import { logger } from '../../Utils/Logger';
import DownloadDirManager from '../Storage/DownloadDirManager';
import fs from '@ohos.file.fs';
import { http } from '@kit.NetworkKit';
import { getSuwayomiSourceExecutor } from './SuwayomiSourceExecutor';

const TAG = 'SuwayomiCacheManager';

/**
 * 缓存状态
 */
export interface CacheStatus {
  mangaId: string;
  chapterId: string;
  totalPages: number;
  cachedPages: number;
  isComplete: boolean;
  cachePath: string;
}

/**
 * 缓存统计信息
 */
export interface CacheStats {
  coverCount: number;
  iconCount: number;
  totalSize: number;
}

/**
 * Suwayomi 缓存管理器单例
 */
export class SuwayomiCacheManager {
  private static instance: SuwayomiCacheManager;

  private constructor() {
    logger.info(TAG, 'Suwayomi缓存管理器初始化');
  }

  public static getInstance(): SuwayomiCacheManager {
    if (!SuwayomiCacheManager.instance) {
      SuwayomiCacheManager.instance = new SuwayomiCacheManager();
    }
    return SuwayomiCacheManager.instance;
  }

  /**
   * 获取章节页面缓存目录
   */
  private getChapterPagesCacheDir(): string {
    return DownloadDirManager.ensureDirectory('suwayomi/chapters');
  }

  /**
   * 清理文件名，移除非法字符
   */
  private sanitizeName(name: string): string {
    return name
      .replace(/[\\/:*?"<>|]/g, '_')
      .replace(/\s+/g, ' ')
      .trim()
      .substring(0, 100);
  }

  /**
   * 获取漫画缓存目录路径
   * 路径: suwayomi/chapters/{mangaTitle}/
   */
  public getMangaCachePath(mangaTitle: string): string {
    if (!DownloadDirManager.isReady()) {
      throw new Error('Download目录未初始化');
    }
    const sanitizedTitle = this.sanitizeName(mangaTitle);
    return DownloadDirManager.ensureDirectory(`suwayomi/chapters/${sanitizedTitle}`);
  }

  /**
   * 获取章节缓存目录路径
   * 路径: suwayomi/chapters/{mangaTitle}/{chapterTitle}/
   */
  public getChapterCachePath(mangaTitle: string, chapterTitle: string): string {
    if (!DownloadDirManager.isReady()) {
      throw new Error('Download目录未初始化');
    }
    const sanitizedManga = this.sanitizeName(mangaTitle);
    const sanitizedChapter = this.sanitizeName(chapterTitle);
    return DownloadDirManager.ensureDirectory(`suwayomi/chapters/${sanitizedManga}/${sanitizedChapter}`);
  }

  /**
   * 获取页面缓存文件路径
   * 路径: suwayomi/chapters/{mangaTitle}/{chapterTitle}/page_XXXX.jpg
   */
  public getPageCachePath(mangaTitle: string, chapterTitle: string, pageIndex: number): string {
    if (!DownloadDirManager.isReady()) {
      throw new Error('Download目录未初始化');
    }
    const chapterPath = this.getChapterCachePath(mangaTitle, chapterTitle);
    return `${chapterPath}/page_${String(pageIndex + 1).padStart(4, '0')}.jpg`;
  }

  /**
   * 检查页面是否已缓存
   */
  public isPageCached(mangaTitle: string, chapterTitle: string, pageIndex: number): boolean {
    try {
      const pagePath = this.getPageCachePath(mangaTitle, chapterTitle, pageIndex);
      fs.accessSync(pagePath);
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * 检查章节是否完全缓存
   */
  public isChapterCached(mangaTitle: string, chapterTitle: string, totalPages: number): boolean {
    for (let i = 0; i < totalPages; i++) {
      if (!this.isPageCached(mangaTitle, chapterTitle, i)) {
        return false;
      }
    }
    return totalPages > 0;
  }

  /**
   * 获取章节缓存状态
   */
  public getChapterCacheStatus(mangaTitle: string, chapterTitle: string, totalPages: number): CacheStatus {
    let cachedPages = 0;
    for (let i = 0; i < totalPages; i++) {
      if (this.isPageCached(mangaTitle, chapterTitle, i)) {
        cachedPages++;
      }
    }
    const status: CacheStatus = {
      mangaId: '',
      chapterId: '',
      totalPages: totalPages,
      cachedPages: cachedPages,
      isComplete: cachedPages === totalPages && totalPages > 0,
      cachePath: this.getChapterCachePath(mangaTitle, chapterTitle)
    };
    return status;
  }

  /**
   * 缓存单个页面
   */
  public async cachePage(
    mangaTitle: string,
    chapterTitle: string,
    pageIndex: number,
    imageUrl: string,
    headers?: Record<string, string>
  ): Promise<boolean> {
    try {
      const pagePath = this.getPageCachePath(mangaTitle, chapterTitle, pageIndex);
      
      // 检查是否已缓存
      if (this.isPageCached(mangaTitle, chapterTitle, pageIndex)) {
        logger.debug(TAG, `页面已缓存: ${pageIndex}`);
        return true;
      }

      // 下载图片
      const httpRequest = http.createHttp();
      const emptyHeaders: Record<string, string> = {};
      const response = await httpRequest.request(imageUrl, {
        method: http.RequestMethod.GET,
        header: headers || emptyHeaders,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });

      if (response.responseCode === 200 && response.result) {
        // 保存到文件
        const file = fs.openSync(pagePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        fs.writeSync(file.fd, response.result as ArrayBuffer);
        fs.closeSync(file.fd);
        logger.debug(TAG, `页面缓存成功: ${pageIndex} -> ${pagePath}`);
        return true;
      } else {
        logger.error(TAG, `下载页面失败: ${response.responseCode}`);
        return false;
      }
    } catch (error) {
      logger.error(TAG, `缓存页面失败: ${error}`);
      return false;
    }
  }

  /**
   * 缓存整个章节
   */
  public async cacheChapter(
    mangaTitle: string,
    chapterTitle: string,
    chapterId: string,
    onProgress?: (current: number, total: number) => void
  ): Promise<boolean> {
    try {
      const executor = getSuwayomiSourceExecutor();
      const pages = await executor.getPages(chapterId);
      const headers = executor.getImageHeaders();

      if (pages.length === 0) {
        logger.warn(TAG, '章节没有页面');
        return false;
      }

      let successCount = 0;
      for (let i = 0; i < pages.length; i++) {
        const success = await this.cachePage(mangaTitle, chapterTitle, i, pages[i].url, headers);
        if (success) {
          successCount++;
        }
        if (onProgress) {
          onProgress(i + 1, pages.length);
        }
      }

      logger.info(TAG, `章节缓存完成: ${successCount}/${pages.length}`);
      return successCount === pages.length;
    } catch (error) {
      logger.error(TAG, `缓存章节失败: ${error}`);
      return false;
    }
  }

  /**
   * 获取缓存的页面路径（如果已缓存）
   */
  public getCachedPagePath(mangaTitle: string, chapterTitle: string, pageIndex: number): string | null {
    try {
      const pagePath = this.getPageCachePath(mangaTitle, chapterTitle, pageIndex);
      fs.accessSync(pagePath);
      return pagePath;
    } catch (error) {
      return null;
    }
  }

  /**
   * 删除章节缓存
   */
  public deleteChapterCache(mangaTitle: string, chapterTitle: string): boolean {
    try {
      const chapterPath = this.getChapterCachePath(mangaTitle, chapterTitle);
      fs.rmdirSync(chapterPath);
      logger.info(TAG, `章节缓存已删除: ${chapterPath}`);
      return true;
    } catch (error) {
      logger.error(TAG, `删除章节缓存失败: ${error}`);
      return false;
    }
  }

  /**
   * 删除漫画缓存
   */
  public deleteMangaCache(mangaTitle: string): boolean {
    try {
      const mangaPath = this.getMangaCachePath(mangaTitle);
      fs.rmdirSync(mangaPath);
      logger.info(TAG, `漫画缓存已删除: ${mangaPath}`);
      return true;
    } catch (error) {
      logger.error(TAG, `删除漫画缓存失败: ${error}`);
      return false;
    }
  }

  // ==================== 封面图片缓存 ====================

  /**
   * 获取Suwayomi缓存根目录
   */
  private getSuwayomiCacheRoot(): string {
    if (!DownloadDirManager.isReady()) {
      throw new Error('Download目录未初始化');
    }
    return DownloadDirManager.ensureDirectory('suwayomi');
  }

  /**
   * 获取封面缓存目录
   */
  private getCoverCacheDir(): string {
    return DownloadDirManager.ensureDirectory('suwayomi/covers');
  }

  /**
   * 获取图源图标缓存目录
   */
  private getSourceIconCacheDir(): string {
    return DownloadDirManager.ensureDirectory('suwayomi/source_icons');
  }

  /**
   * 生成文件名安全的哈希值
   */
  private hashString(str: string): string {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash;
    }
    return Math.abs(hash).toString(16);
  }

  /**
   * 从URL中提取文件扩展名
   */
  private getExtensionFromUrl(url: string): string {
    try {
      const urlPath = url.split('?')[0];
      const lastDot = urlPath.lastIndexOf('.');
      if (lastDot > 0) {
        const ext = urlPath.substring(lastDot + 1).toLowerCase();
        if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'avif'].includes(ext)) {
          return ext;
        }
      }
    } catch (e) {
      // ignore
    }
    return 'jpg';
  }

  /**
   * 获取封面缓存文件路径
   * @param mangaId 漫画ID
   * @param coverUrl 封面URL（用于生成唯一文件名）
   */
  public getCoverCachePath(mangaId: string, coverUrl: string): string {
    const cacheDir = this.getCoverCacheDir();
    const ext = this.getExtensionFromUrl(coverUrl);
    const hash = this.hashString(coverUrl);
    return `${cacheDir}/${mangaId}_${hash}.${ext}`;
  }

  /**
   * 检查封面是否已缓存
   */
  public isCoverCached(mangaId: string, coverUrl: string): boolean {
    try {
      const cachePath = this.getCoverCachePath(mangaId, coverUrl);
      fs.accessSync(cachePath);
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * 获取缓存的封面路径（如果已缓存）
   */
  public getCachedCoverPath(mangaId: string, coverUrl: string): string | null {
    try {
      const cachePath = this.getCoverCachePath(mangaId, coverUrl);
      fs.accessSync(cachePath);
      return cachePath;
    } catch (error) {
      return null;
    }
  }

  /**
   * 缓存封面图片
   * @param mangaId 漫画ID
   * @param coverUrl 封面URL
   * @param headers 请求头（用于认证）
   * @returns 缓存后的本地路径，失败返回null
   */
  public async cacheCover(
    mangaId: string,
    coverUrl: string,
    headers?: Record<string, string>
  ): Promise<string | null> {
    try {
      // 检查是否已缓存
      const existingPath = this.getCachedCoverPath(mangaId, coverUrl);
      if (existingPath) {
        logger.debug(TAG, `封面已缓存: ${mangaId}`);
        return existingPath;
      }

      const cachePath = this.getCoverCachePath(mangaId, coverUrl);

      // 下载图片
      const httpRequest = http.createHttp();
      const emptyHeaders: Record<string, string> = {};
      const response = await httpRequest.request(coverUrl, {
        method: http.RequestMethod.GET,
        header: headers || emptyHeaders,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 30000
      });

      httpRequest.destroy();

      if (response.responseCode === 200 && response.result) {
        const file = fs.openSync(cachePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        fs.writeSync(file.fd, response.result as ArrayBuffer);
        fs.closeSync(file.fd);
        logger.debug(TAG, `封面缓存成功: ${mangaId} -> ${cachePath}`);
        return cachePath;
      } else {
        logger.error(TAG, `下载封面失败: ${response.responseCode}`);
        return null;
      }
    } catch (error) {
      logger.error(TAG, `缓存封面失败: ${error}`);
      return null;
    }
  }

  // ==================== 图源图标缓存 ====================

  /**
   * 获取图源图标缓存文件路径
   * @param sourceId 图源ID
   * @param iconUrl 图标URL
   */
  public getSourceIconCachePath(sourceId: string, iconUrl: string): string {
    const cacheDir = this.getSourceIconCacheDir();
    const ext = this.getExtensionFromUrl(iconUrl);
    const safeSourceId = sourceId.replace(/[^a-zA-Z0-9]/g, '_');
    return `${cacheDir}/${safeSourceId}.${ext}`;
  }

  /**
   * 检查图源图标是否已缓存
   */
  public isSourceIconCached(sourceId: string, iconUrl: string): boolean {
    try {
      const cachePath = this.getSourceIconCachePath(sourceId, iconUrl);
      fs.accessSync(cachePath);
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * 获取缓存的图源图标路径（如果已缓存）
   */
  public getCachedSourceIconPath(sourceId: string, iconUrl: string): string | null {
    try {
      const cachePath = this.getSourceIconCachePath(sourceId, iconUrl);
      fs.accessSync(cachePath);
      return cachePath;
    } catch (error) {
      return null;
    }
  }

  /**
   * 缓存图源图标
   * @param sourceId 图源ID
   * @param iconUrl 图标URL
   * @param headers 请求头
   * @returns 缓存后的本地路径，失败返回null
   */
  public async cacheSourceIcon(
    sourceId: string,
    iconUrl: string,
    headers?: Record<string, string>
  ): Promise<string | null> {
    try {
      // 检查是否已缓存
      const existingPath = this.getCachedSourceIconPath(sourceId, iconUrl);
      if (existingPath) {
        logger.debug(TAG, `图源图标已缓存: ${sourceId}`);
        return existingPath;
      }

      const cachePath = this.getSourceIconCachePath(sourceId, iconUrl);

      // 下载图片
      const httpRequest = http.createHttp();
      const emptyHeaders: Record<string, string> = {};
      const response = await httpRequest.request(iconUrl, {
        method: http.RequestMethod.GET,
        header: headers || emptyHeaders,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 30000
      });

      httpRequest.destroy();

      if (response.responseCode === 200 && response.result) {
        const file = fs.openSync(cachePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        fs.writeSync(file.fd, response.result as ArrayBuffer);
        fs.closeSync(file.fd);
        logger.debug(TAG, `图源图标缓存成功: ${sourceId} -> ${cachePath}`);
        return cachePath;
      } else {
        logger.error(TAG, `下载图源图标失败: ${response.responseCode}`);
        return null;
      }
    } catch (error) {
      logger.error(TAG, `缓存图源图标失败: ${error}`);
      return null;
    }
  }

  // ==================== 缓存管理 ====================

  /**
   * 获取缓存统计信息
   */
  public getCacheStats(): CacheStats {
    let coverCount = 0;
    let iconCount = 0;
    let totalSize = 0;

    try {
      // 统计封面缓存
      const coverDir = this.getCoverCacheDir();
      const coverFiles = fs.listFileSync(coverDir);
      coverCount = coverFiles.length;
      for (const file of coverFiles) {
        try {
          const stat = fs.statSync(`${coverDir}/${file}`);
          totalSize += stat.size;
        } catch (e) {
          // ignore
        }
      }

      // 统计图源图标缓存
      const iconDir = this.getSourceIconCacheDir();
      const iconFiles = fs.listFileSync(iconDir);
      iconCount = iconFiles.length;
      for (const file of iconFiles) {
        try {
          const stat = fs.statSync(`${iconDir}/${file}`);
          totalSize += stat.size;
        } catch (e) {
          // ignore
        }
      }
    } catch (error) {
      logger.warn(TAG, `获取缓存统计失败: ${error}`);
    }

    const result: CacheStats = {
      coverCount: coverCount,
      iconCount: iconCount,
      totalSize: totalSize
    };
    return result;
  }

  /**
   * 清除所有封面缓存
   */
  public clearCoverCache(): boolean {
    try {
      const coverDir = this.getCoverCacheDir();
      const files = fs.listFileSync(coverDir);
      for (const file of files) {
        try {
          fs.unlinkSync(`${coverDir}/${file}`);
        } catch (e) {
          // ignore
        }
      }
      logger.info(TAG, `封面缓存已清除: ${files.length} 个文件`);
      return true;
    } catch (error) {
      logger.error(TAG, `清除封面缓存失败: ${error}`);
      return false;
    }
  }

  /**
   * 清除所有图源图标缓存
   */
  public clearSourceIconCache(): boolean {
    try {
      const iconDir = this.getSourceIconCacheDir();
      const files = fs.listFileSync(iconDir);
      for (const file of files) {
        try {
          fs.unlinkSync(`${iconDir}/${file}`);
        } catch (e) {
          // ignore
        }
      }
      logger.info(TAG, `图源图标缓存已清除: ${files.length} 个文件`);
      return true;
    } catch (error) {
      logger.error(TAG, `清除图源图标缓存失败: ${error}`);
      return false;
    }
  }

  /**
   * 清除所有Suwayomi缓存
   */
  public clearAllCache(): boolean {
    const coverResult = this.clearCoverCache();
    const iconResult = this.clearSourceIconCache();
    return coverResult && iconResult;
  }
}

// 导出单例
export default SuwayomiCacheManager.getInstance();
