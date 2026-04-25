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
import { DataManager, OnlinePageInfo } from '../Data/DataManager';
import { DatabaseManager } from '../Database/DatabaseManager';
import { eventBus, GameEvent, MangaCacheUpdatedPayload } from '../EventBus';
import fs from '@ohos.file.fs';

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
  private databaseManager: DatabaseManager;
  
  private constructor() {
    this.permanentCacheManager = PermanentImageCacheManager.getInstance();
    this.novelCacheManager = getNovelChapterCacheManager();
    this.dataManager = DataManager.getInstance();
    this.databaseManager = DatabaseManager.getInstance();
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
        const chapterTotalPages = Math.max(pages.length, chapter.pageCount || 0);
        totalPageCount += chapterTotalPages;
        
        // 统计已缓存的页面：优先识别新CBZ归档，再兼容旧localPath散图。
        let chapterCachedPages = 0;
        let chapterCacheSize = 0;

        const archivePath = chapter.downloadPath || '';
        const resolvedArchivePath = this.resolveReadableArchivePath(archivePath);
        const hasArchive = resolvedArchivePath.length > 0;
        if (hasArchive) {
          chapterCachedPages = chapterTotalPages;
          chapterCacheSize = this.getFileSize(resolvedArchivePath);
        } else {
          for (const page of pages) {
            const cachedPath = await this.resolveCachedOnlinePagePath(sourceId, mangaId, chapter.id, page);
            if (cachedPath.length > 0) {
              chapterCachedPages++;
              chapterCacheSize += page.fileSize || this.getFileSize(cachedPath);
            }
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
          cacheSize: chapterCacheSize,
          cachePath: hasArchive ? resolvedArchivePath : undefined
        });
      }
      
      const calculatedCacheSize = chapterStats.reduce((sum, ch) => sum + ch.cacheSize, 0);
      if (calculatedCacheSize > 0) {
        totalCacheSize = calculatedCacheSize;
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

  private fileExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_error) {
      return false;
    }
  }

  private getFileSize(path: string): number {
    try {
      const stat = fs.statSync(path);
      return stat.size;
    } catch (_error) {
      return 0;
    }
  }

  private resolveReadableArchivePath(archivePath: string): string {
    const normalizedArchivePath = this.normalizeFileSystemPath(archivePath);
    if (normalizedArchivePath.length === 0 || !normalizedArchivePath.toLowerCase().endsWith('.cbz')) {
      return '';
    }
    if (this.fileExists(normalizedArchivePath)) {
      return normalizedArchivePath;
    }
    return this.recoverTemporaryArchiveFile(normalizedArchivePath);
  }

  private recoverTemporaryArchiveFile(archivePath: string): string {
    const tempPaths = this.buildArchiveTempPathCandidates(archivePath);
    for (let i = 0; i < tempPaths.length; i++) {
      const tempPath = tempPaths[i];
      if (!this.fileExists(tempPath)) {
        continue;
      }

      try {
        this.deleteFileIfExists(archivePath);
        fs.renameSync(tempPath, archivePath);
        this.deleteArchiveTempFiles(archivePath);
        logger.info(TAG, `已恢复未完成CBZ缓存: ${tempPath} -> ${archivePath}`);
        return archivePath;
      } catch (error) {
        logger.warn(TAG, `恢复未完成CBZ缓存失败: ${tempPath}, ${String(error)}`);
      }
    }
    return '';
  }

  private deleteFileIfExists(path: string): void {
    try {
      if (this.fileExists(path)) {
        fs.unlinkSync(path);
      }
    } catch (error) {
      logger.warn(TAG, `删除缓存文件失败: ${path}, ${String(error)}`);
    }
  }

  private deleteArchiveTempFiles(archivePath: string): void {
    const tempPaths = this.buildArchiveTempPathCandidates(archivePath);
    for (let i = 0; i < tempPaths.length; i++) {
      this.deleteFileIfExists(tempPaths[i]);
    }
  }

  private buildArchiveTempPathCandidates(archivePath: string): string[] {
    const legacyTempArchivePath = `${archivePath}.tmp`;
    const zipTempArchivePath = `${archivePath}.tmp.zip`;
    const paths: string[] = [];
    paths.push(zipTempArchivePath);
    paths.push(`${zipTempArchivePath}.zip`);
    paths.push(legacyTempArchivePath);
    paths.push(`${legacyTempArchivePath}.zip`);
    return this.deduplicatePaths(paths);
  }

  private deduplicatePaths(paths: string[]): string[] {
    const result: string[] = [];
    for (let i = 0; i < paths.length; i++) {
      const currentPath = paths[i];
      let exists = false;
      for (let j = 0; j < result.length; j++) {
        if (result[j] === currentPath) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        result.push(currentPath);
      }
    }
    return result;
  }

  private async resolveCachedOnlinePagePath(
    sourceId: number,
    mangaId: string,
    chapterId: string,
    page: OnlinePageInfo
  ): Promise<string> {
    const localPath = this.normalizeFileSystemPath(page.localPath || '');
    if (localPath.length > 0 && this.fileExists(localPath)) {
      return localPath;
    }

    const fallbackPath = await this.permanentCacheManager.getCachedImagePath(
      sourceId,
      mangaId,
      chapterId,
      page.pageNumber,
      page.imageUrl
    );
    if (fallbackPath && fallbackPath.length > 0 && this.fileExists(fallbackPath)) {
      return fallbackPath;
    }
    return '';
  }

  private normalizeFileSystemPath(path: string): string {
    const trimmed = path.trim();
    if (trimmed.length === 0) {
      return '';
    }
    if (trimmed.startsWith('file://')) {
      return trimmed.substring(7);
    }
    if (trimmed.startsWith('/')) {
      return trimmed;
    }
    if (trimmed.startsWith('storage/') || trimmed.startsWith('data/')) {
      return `/${trimmed}`;
    }
    return trimmed;
  }

  private decodeLegacyBookUrlFromCompositeId(bookId: string): string {
    const separatorIndex = bookId.indexOf('_');
    if (separatorIndex <= 0 || separatorIndex >= bookId.length - 1) {
      return '';
    }
    const encodedBookUrl = bookId.substring(separatorIndex + 1).trim();
    if (encodedBookUrl.length <= 0) {
      return '';
    }
    let decodedBookUrl = '';
    try {
      decodedBookUrl = decodeURIComponent(encodedBookUrl);
    } catch (_error) {
      return '';
    }
    const normalized = decodedBookUrl.trim();
    if (
      normalized.length <= 0 ||
      normalized === bookId ||
      (!normalized.startsWith('http://') && !normalized.startsWith('https://') && !normalized.startsWith('file://'))
    ) {
      return '';
    }
    return normalized;
  }

  private mergeNovelCacheKind(
    first: 'text' | 'audio' | 'mixed' | undefined,
    second: 'text' | 'audio' | 'mixed' | undefined
  ): 'text' | 'audio' | 'mixed' | undefined {
    if (first === 'mixed' || second === 'mixed') {
      return 'mixed';
    }
    if (!first) {
      return second;
    }
    if (!second) {
      return first;
    }
    if (first === second) {
      return first;
    }
    return 'mixed';
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
      
      // 获取主key（组合bookId）缓存信息
      const primaryCacheInfo = await this.novelCacheManager.getBookCacheInfo(bookId);
      
      // 获取已缓存的章节索引
      const primaryCachedIndexes = await this.novelCacheManager.getCachedChapterIndexes(
        bookId,
        totalChapters || primaryCacheInfo.totalChapterCount || 0
      );
      const mergedCachedIndexes = new Set<number>();
      primaryCachedIndexes.forEach((index: number) => mergedCachedIndexes.add(index));

      let mergedCacheSize = primaryCacheInfo.cacheSize;
      let mergedLastCacheTime = primaryCacheInfo.lastCacheTime;
      let mergedCacheKind: 'text' | 'audio' | 'mixed' | undefined = primaryCacheInfo.cacheKind;

      const legacyBookUrl = this.decodeLegacyBookUrlFromCompositeId(bookId);
      if (legacyBookUrl.length > 0 && legacyBookUrl !== bookId) {
        logger.debug(TAG, `小说缓存状态启用旧bookUrl兼容: composite=${bookId}, legacy=${legacyBookUrl}`);
        const legacyCacheInfo = await this.novelCacheManager.getBookCacheInfo(legacyBookUrl);
        const legacyCachedIndexes = await this.novelCacheManager.getCachedChapterIndexes(
          legacyBookUrl,
          totalChapters || legacyCacheInfo.totalChapterCount || 0
        );
        legacyCachedIndexes.forEach((index: number) => mergedCachedIndexes.add(index));
        mergedCacheSize += legacyCacheInfo.cacheSize;
        mergedLastCacheTime = Math.max(mergedLastCacheTime, legacyCacheInfo.lastCacheTime);
        mergedCacheKind = this.mergeNovelCacheKind(mergedCacheKind, legacyCacheInfo.cacheKind);
      }

      const cachedChapterCount = Math.max(primaryCacheInfo.cachedChapterCount, mergedCachedIndexes.size);

      // 构建章节状态列表
      const chapterStats: ChapterCacheStatus[] = [];
      const totalChapterCount = totalChapters || primaryCacheInfo.totalChapterCount || cachedChapterCount;
      
      for (let i = 0; i < totalChapterCount; i++) {
        const isCached = mergedCachedIndexes.has(i);
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
        cachedChapterCount: cachedChapterCount,
        totalChapterCount: totalChapterCount,
        cachedPageCount: cachedChapterCount,  // 小说用章节数代替
        totalPageCount: totalChapterCount,
        cacheSize: mergedCacheSize,
        downloadWhileReadingEnabled: true,  // 小说默认开启
        chapterStats: chapterStats,
        lastCacheTime: mergedLastCacheTime
      };
      
      logger.info(
        TAG,
        `小说缓存状态: cached=${cachedChapterCount}/${totalChapterCount}章, size=${this.formatSize(mergedCacheSize)}, kind=${mergedCacheKind || 'none'}`
      );
      
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
        await this.clearMangaArchiveFiles(contentId);
        
        // 2. 清理数据库中的localPath字段
        await this.dataManager.clearMangaCacheRecords(contentId);
        eventBus.publish(
          GameEvent.MANGA_CACHE_UPDATED,
          new MangaCacheUpdatedPayload(contentId, '', sourceId, '', 'clear_cache')
        );
        
        logger.info(TAG, `清理漫画缓存成功: ${contentId}`);
      } else if (contentType === CacheContentType.NOVEL) {
        await this.novelCacheManager.clearBookCache(contentId);
        const legacyBookUrl = this.decodeLegacyBookUrlFromCompositeId(contentId);
        if (legacyBookUrl.length > 0 && legacyBookUrl !== contentId) {
          await this.novelCacheManager.clearBookCache(legacyBookUrl);
          logger.info(TAG, `已同步清理小说旧版bookUrl缓存: ${legacyBookUrl}`);
        }
        logger.info(TAG, `清理小说缓存成功: ${contentId}`);
      }
      return true;
    } catch (error) {
      logger.error(TAG, `清理缓存失败: ${String(error)}`);
      return false;
    }
  }

  private async clearMangaArchiveFiles(mangaId: string): Promise<void> {
    const chapters = await this.dataManager.getOnlineComicChapters(mangaId);
    for (let i = 0; i < chapters.length; i++) {
      const archivePath = this.normalizeFileSystemPath(chapters[i].downloadPath || '');
      if (archivePath.toLowerCase().endsWith('.cbz')) {
        this.deleteFileIfExists(archivePath);
        this.deleteArchiveTempFiles(archivePath);
        logger.info(TAG, `已清理漫画CBZ缓存文件族: ${archivePath}`);
      }
    }
    await this.databaseManager.executeSql(
      'UPDATE online_chapter SET isDownloaded = 0, downloadPath = NULL WHERE comicId = ?',
      [mangaId]
    );
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
