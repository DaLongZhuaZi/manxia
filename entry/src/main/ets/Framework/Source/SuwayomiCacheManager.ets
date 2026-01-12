/**
 * Suwayomi 图片缓存管理器
 * 将 Suwayomi 服务器上的漫画图片缓存到本地 Download/com.dlzz.manxia/manga 目录
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
   * 获取漫画缓存目录路径
   */
  public getMangaCachePath(mangaTitle: string): string {
    if (!DownloadDirManager.isReady()) {
      throw new Error('Download目录未初始化');
    }
    return DownloadDirManager.getMangaDownloadPath(mangaTitle);
  }

  /**
   * 获取章节缓存目录路径
   */
  public getChapterCachePath(mangaTitle: string, chapterTitle: string): string {
    if (!DownloadDirManager.isReady()) {
      throw new Error('Download目录未初始化');
    }
    return DownloadDirManager.getMangaDownloadPath(mangaTitle, chapterTitle);
  }

  /**
   * 获取页面缓存文件路径
   */
  public getPageCachePath(mangaTitle: string, chapterTitle: string, pageIndex: number): string {
    if (!DownloadDirManager.isReady()) {
      throw new Error('Download目录未初始化');
    }
    return DownloadDirManager.getImageSavePath(mangaTitle, chapterTitle, pageIndex, 'jpg');
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
    return {
      mangaId: '',
      chapterId: '',
      totalPages: totalPages,
      cachedPages: cachedPages,
      isComplete: cachedPages === totalPages && totalPages > 0,
      cachePath: this.getChapterCachePath(mangaTitle, chapterTitle)
    };
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
      const response = await httpRequest.request(imageUrl, {
        method: http.RequestMethod.GET,
        header: headers || {},
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
}

// 导出单例
export default SuwayomiCacheManager.getInstance();
