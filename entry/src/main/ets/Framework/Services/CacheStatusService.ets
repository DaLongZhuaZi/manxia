/**
 * 缓存状态服务
 * 提供统一接口查询漫画/小说的缓存状态
 * 整合 PermanentImageCacheManager 和 NovelChapterCacheManager 的数据
 * 
 * 文件路径: entry/src/main/ets/Framework/Services/CacheStatusService.ets
 */

import { logger } from '../../Utils/Logger';
import { PermanentImageCacheManager } from '../Cache/PermanentImageCacheManager';
import { getNovelChapterCacheManager, NovelChapterCacheManager } from '../Novel/NovelChapterCacheManager';
import { DataManager } from '../Data/DataManager';

const TAG = 'CacheStatusService';

/**
 * 内容类型枚举
 */
export enum CacheContentType {
  MANGA = 'manga',
  NOVEL = 'novel'
}

/**
 * 章节缓存状态
 */
export interface ChapterCacheStatus {
  chapterId: string;
  chapterTitle: string;
  chapterIndex: number;
  isCached: boolean;
  cachedPageCount: number;
  totalPageCount: number;
  cacheSize: number;  // 字节
  cachePath?: string;
}

/**
 * 内容缓存统计信息
 */
export interface ContentCacheStats {
  contentId: string;
  contentType: CacheContentType;
  title: string;
  sourceId: number;
  
  // 缓存统计
  cachedChapterCount: number;
  totalChapterCount: number;
  cachedPageCount: number;  // 仅漫画有效
  totalPageCount: number;   // 仅漫画有效
  cacheSize: number;        // 总缓存大小（字节）
  
  // 下载状态
  downloadWhileReadingEnabled: boolean;
  
  // 章节详情
  chapterStats: ChapterCacheStatus[];
  
  // 时间信息
  lastCacheTime: number;
}

/**
 * 缓存状态服务类
 */
export class CacheStatusService {
  private static instance: CacheStatusService | null = null;
  private permanentCacheManager: PermanentImageCacheManager;
  private novelCacheManager: NovelChapterCacheManager;
  private dataManager: DataManager;
  
  private constructor() {
    this.permanentCacheManager = PermanentImageCacheManager.getInstance();
    this.novelCacheManager = getNovelChapterCacheManager();
    this.dataManager = DataManager.getInstance();
  }
  
  public static getInstance(): CacheStatusService {
    if (!CacheStatusService.instance) {
      CacheStatusService.instance = new CacheStatusService();
    }
    return CacheStatusService.instance;
  }
  
  /**
   * 获取漫画缓存状态
   * @param sourceId 图源ID
   * @param mangaId 漫画ID
   * @param mangaTitle 漫画标题（可选）
   */
  async getMangaCacheStatus(
    sourceId: number,
    mangaId: string,
    mangaTitle?: string
  ): Promise<ContentCacheStats> {
    try {
      logger.info(TAG, `获取漫画缓存状态: sourceId=${sourceId}, mangaId=${mangaId}, title=${mangaTitle}`);
      
      // 获取边看边下载设置
      const config = await this.permanentCacheManager.getSourceCacheConfig(sourceId);
      const downloadWhileReadingEnabled = config.downloadWhileReading;
      
      // 获取漫画的缓存统计
      const mangaCacheStats = await this.permanentCacheManager.getSourceMangaCacheStats(sourceId);
      const mangaStats = mangaCacheStats.find(s => s.mangaId === mangaId);
      
      // 从数据库获取章节信息（使用已有的 getOnlineComicChapters 方法）
      const chapters = await this.dataManager.getOnlineComicChapters(mangaId);
      const totalChapterCount = chapters.length;
      
      logger.info(TAG, `漫画 [${mangaTitle}] 章节数: ${totalChapterCount}`);
      
      // 统计每个章节的缓存状态
      const chapterStats: ChapterCacheStatus[] = [];
      let cachedChapterCount = 0;
      let cachedPageCount = 0;
      let totalPageCount = 0;
      let totalCacheSize = mangaStats?.totalSize || 0;
      
      for (const chapter of chapters) {
        // 获取章节的页面列表（使用已有的 getOnlineChapterPages 方法）
        const pages = await this.dataManager.getOnlineChapterPages(chapter.id);
        const chapterTotalPages = pages.length;
        totalPageCount += chapterTotalPages;
        
        // 统计已缓存的页面（通过 localPath 是否存在判断）
        let chapterCachedPages = 0;
        let chapterCacheSize = 0;
        
        for (const page of pages) {
          // 如果 localPath 存在，表示页面已缓存
          if (page.localPath && page.localPath.length > 0) {
            chapterCachedPages++;
            chapterCacheSize += page.fileSize || 0;
          }
        }
        
        cachedPageCount += chapterCachedPages;
        
        // 判断章节是否完全缓存
        const isChapterCached = chapterTotalPages > 0 && chapterCachedPages === chapterTotalPages;
        if (isChapterCached) {
          cachedChapterCount++;
        }
        
        chapterStats.push({
          chapterId: chapter.id,
          chapterTitle: chapter.title || `第${chapter.index + 1}话`,
          chapterIndex: chapter.index,
          isCached: isChapterCached,
          cachedPageCount: chapterCachedPages,
          totalPageCount: chapterTotalPages,
          cacheSize: chapterCacheSize
        });
      }
      
      // 如果没有从mangaStats获取到大小，使用统计的大小
      if (totalCacheSize === 0) {
        totalCacheSize = chapterStats.reduce((sum, ch) => sum + ch.cacheSize, 0);
      }
      
      const result: ContentCacheStats = {
        contentId: mangaId,
        contentType: CacheContentType.MANGA,
        title: mangaTitle || mangaStats?.mangaTitle || mangaId,
        sourceId: sourceId,
        cachedChapterCount: cachedChapterCount,
        totalChapterCount: totalChapterCount,
        cachedPageCount: cachedPageCount,
        totalPageCount: totalPageCount,
        cacheSize: totalCacheSize,
        downloadWhileReadingEnabled: downloadWhileReadingEnabled,
        chapterStats: chapterStats,
        lastCacheTime: Date.now()
      };
      
      logger.info(TAG, `漫画缓存状态: cached=${cachedChapterCount}/${totalChapterCount}章, pages=${cachedPageCount}/${totalPageCount}, size=${this.formatSize(totalCacheSize)}`);
      
      return result;
    } catch (error) {
      logger.error(TAG, `获取漫画缓存状态失败: ${String(error)}`);
      return this.createEmptyStats(mangaId, CacheContentType.MANGA, sourceId, mangaTitle);
    }
  }
  
  /**
   * 获取小说缓存状态
   * @param bookId 小说ID
   * @param bookTitle 小说标题（可选）
   * @param totalChapters 总章节数（可选）
   */
  async getNovelCacheStatus(
    bookId: string,
    bookTitle?: string,
    totalChapters?: number
  ): Promise<ContentCacheStats> {
    try {
      logger.info(TAG, `获取小说缓存状态: bookId=${bookId}`);
      
      // 获取小说缓存信息
      const cacheInfo = await this.novelCacheManager.getBookCacheInfo(bookId);
      
      // 获取已缓存的章节索引
      const cachedIndexes = await this.novelCacheManager.getCachedChapterIndexes(
        bookId,
        totalChapters || cacheInfo.totalChapterCount || 0
      );
      
      // 构建章节状态列表
      const chapterStats: ChapterCacheStatus[] = [];
      const totalChapterCount = totalChapters || cacheInfo.totalChapterCount || cachedIndexes.size;
      
      for (let i = 0; i < totalChapterCount; i++) {
        const isCached = cachedIndexes.has(i);
        chapterStats.push({
          chapterId: `${bookId}_chapter_${i}`,
          chapterTitle: `第${i + 1}章`,
          chapterIndex: i,
          isCached: isCached,
          cachedPageCount: isCached ? 1 : 0,
          totalPageCount: 1,
          cacheSize: 0  // 小说章节大小需要单独计算
        });
      }
      
      const result: ContentCacheStats = {
        contentId: bookId,
        contentType: CacheContentType.NOVEL,
        title: bookTitle || bookId,
        sourceId: 0,  // 小说可能没有sourceId
        cachedChapterCount: cacheInfo.cachedChapterCount,
        totalChapterCount: totalChapterCount,
        cachedPageCount: cacheInfo.cachedChapterCount,  // 小说用章节数代替
        totalPageCount: totalChapterCount,
        cacheSize: cacheInfo.cacheSize,
        downloadWhileReadingEnabled: true,  // 小说默认开启
        chapterStats: chapterStats,
        lastCacheTime: cacheInfo.lastCacheTime
      };
      
      logger.info(TAG, `小说缓存状态: cached=${cacheInfo.cachedChapterCount}/${totalChapterCount}章, size=${this.formatSize(cacheInfo.cacheSize)}`);
      
      return result;
    } catch (error) {
      logger.error(TAG, `获取小说缓存状态失败: ${String(error)}`);
      return this.createEmptyStats(bookId, CacheContentType.NOVEL, 0, bookTitle);
    }
  }
  
  /**
   * 根据内容类型获取缓存状态
   */
  async getCacheStatus(
    contentType: CacheContentType,
    contentId: string,
    sourceId: number,
    title?: string,
    totalChapters?: number
  ): Promise<ContentCacheStats> {
    if (contentType === CacheContentType.MANGA) {
      return this.getMangaCacheStatus(sourceId, contentId, title);
    } else {
      return this.getNovelCacheStatus(contentId, title, totalChapters);
    }
  }
  
  /**
   * 检查边看边下载是否开启
   */
  async isDownloadWhileReadingEnabled(sourceId: number): Promise<boolean> {
    try {
      const config = await this.permanentCacheManager.getSourceCacheConfig(sourceId);
      return config.downloadWhileReading;
    } catch (error) {
      logger.error(TAG, `检查边看边下载设置失败: ${String(error)}`);
      return true;  // 默认开启
    }
  }
  
  /**
   * 获取所有已缓存的漫画列表
   * [改进] 直接从数据库查询有缓存页面的漫画，而不是依赖文件系统扫描
   * 这样可以获取正确的漫画标题和完整的缓存信息
   */
  async getAllCachedMangas(sourceId: number): Promise<ContentCacheStats[]> {
    try {
      // 使用DataManager的新方法获取已缓存的漫画列表
      const cachedMangas = await this.dataManager.getCachedMangasBySource(sourceId);
      const results: ContentCacheStats[] = [];
      
      for (const manga of cachedMangas) {
        if (manga.mangaId) {
          const cacheStatus = await this.getMangaCacheStatus(
            sourceId,
            manga.mangaId,
            manga.mangaTitle
          );
          
          // 只添加有实际缓存的漫画
          if (cacheStatus.cachedPageCount > 0) {
            results.push(cacheStatus);
          }
        }
      }
      
      logger.info(TAG, `获取已缓存漫画列表: sourceId=${sourceId}, 找到 ${results.length} 部漫画`);
      return results;
    } catch (error) {
      logger.error(TAG, `获取已缓存漫画列表失败: ${String(error)}`);
      return [];
    }
  }
  
  /**
   * 清理指定内容的缓存
   * [改进] 同时清理文件系统和数据库中的缓存记录
   */
  async clearContentCache(
    contentType: CacheContentType,
    contentId: string,
    sourceId?: number
  ): Promise<boolean> {
    try {
      if (contentType === CacheContentType.MANGA && sourceId !== undefined) {
        // 1. 删除文件系统中的缓存文件
        await this.permanentCacheManager.deleteMangaCache(sourceId, contentId);
        
        // 2. 清理数据库中的localPath字段
        await this.dataManager.clearMangaCacheRecords(contentId);
        
        logger.info(TAG, `清理漫画缓存成功: ${contentId}`);
      } else if (contentType === CacheContentType.NOVEL) {
        await this.novelCacheManager.clearBookCache(contentId);
        logger.info(TAG, `清理小说缓存成功: ${contentId}`);
      }
      return true;
    } catch (error) {
      logger.error(TAG, `清理缓存失败: ${String(error)}`);
      return false;
    }
  }
  
  /**
   * 创建空的统计信息
   */
  private createEmptyStats(
    contentId: string,
    contentType: CacheContentType,
    sourceId: number,
    title?: string
  ): ContentCacheStats {
    return {
      contentId: contentId,
      contentType: contentType,
      title: title || contentId,
      sourceId: sourceId,
      cachedChapterCount: 0,
      totalChapterCount: 0,
      cachedPageCount: 0,
      totalPageCount: 0,
      cacheSize: 0,
      downloadWhileReadingEnabled: true,
      chapterStats: [],
      lastCacheTime: 0
    };
  }
  
  /**
   * 格式化文件大小
   */
  formatSize(bytes: number): string {
    if (bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    const k = 1024;
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return (bytes / Math.pow(k, i)).toFixed(2) + ' ' + units[i];
  }
  
  /**
   * 计算缓存进度百分比
   */
  calculateProgress(stats: ContentCacheStats): number {
    if (stats.contentType === CacheContentType.MANGA) {
      if (stats.totalPageCount === 0) return 0;
      return Math.round((stats.cachedPageCount / stats.totalPageCount) * 100);
    } else {
      if (stats.totalChapterCount === 0) return 0;
      return Math.round((stats.cachedChapterCount / stats.totalChapterCount) * 100);
    }
  }
}

/**
 * 获取缓存状态服务实例
 */
export function getCacheStatusService(): CacheStatusService {
  return CacheStatusService.getInstance();
}
