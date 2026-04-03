// 文件路径: src/main/ets/Framework/Storage/StorageAnalyzer.ets
/**
 * 存储分析器
 * 统一管理和分析应用的所有存储使用情况
 */

import { fileIo, storageStatistics } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { logger } from '../../Utils/Logger';
import { SandboxManager } from './SandboxManager';
import { ImageCacheManager } from '../Cache/ImageCacheManager';
import { DatabaseManager } from '../Database/DatabaseManager';
import { uiContextManager } from '../Managers/UIContextManager';
import { BusinessError } from '@kit.BasicServicesKit';
import DownloadDirManager from './DownloadDirManager';

const TAG = 'StorageAnalyzer';

/**
 * 存储项类型
 */
export enum StorageType {
  // === 应用沙箱目录 (context.filesDir) ===
  IMAGE_CACHE = 'IMAGE_CACHE',           // 图片内存缓存
  DATABASE = 'DATABASE',                  // 数据库 (context.databaseDir)
  COMIC_FILES = 'COMIC_FILES',           // 本地漫画文件 (filesDir/comics)
  COVER_FILES = 'COVER_FILES',           // 封面文件 (filesDir/covers)
  LIBRARY_COVERS = 'LIBRARY_COVERS',     // 书库持久化封面 (filesDir/library_covers)
  CHAPTER_FILES = 'CHAPTER_FILES',       // 章节文件 (filesDir/chapters)
  TEMP_FILES = 'TEMP_FILES',             // 临时文件 (filesDir/temp)
  PLUGIN_FILES = 'PLUGIN_FILES',         // 插件文件 (filesDir/plugins)
  PERMANENT_CACHE = 'PERMANENT_CACHE',   // 永久图片缓存 (filesDir/permanent_cache)
  EBOOK_FILES = 'EBOOK_FILES',           // 电子书文件 (filesDir/ebooks)
  SYSTEM_CACHE = 'SYSTEM_CACHE',         // 系统缓存目录 (context.cacheDir)
  
  // === Download文件夹目录 (/Download/com.dlzz.manxia/) ===
  SUWAYOMI_COVERS = 'SUWAYOMI_COVERS',           // Suwayomi封面缓存 (suwayomi/covers)
  SUWAYOMI_SOURCE_ICONS = 'SUWAYOMI_SOURCE_ICONS', // Suwayomi图源图标 (suwayomi/source_icons)
  SUWAYOMI_CHAPTERS = 'SUWAYOMI_CHAPTERS',       // Suwayomi章节页面 (suwayomi/chapters)
  KOMGA_COVERS = 'KOMGA_COVERS',                 // Komga封面缓存 (filesDir/komga_cache/covers)
  KOMGA_CHAPTERS = 'KOMGA_CHAPTERS',             // Komga章节页面 (filesDir/komga_cache/chapters)
  DOWNLOAD_MANGA = 'DOWNLOAD_MANGA'              // 下载的漫画 (manga/)
}

/**
 * 存储项信息
 */
export interface StorageItem {
  type: StorageType;
  name: string;
  description: string;
  size: number;                          // 字节
  fileCount: number;                     // 文件数量
  path: string;                          // 存储路径
  canClear: boolean;                     // 是否可清理
  lastModified: number;                  // 最后修改时间
}

/**
 * 递归删除结果
 */
interface DeleteRecursiveResult {
  size: number;
  count: number;
}

/**
 * 存储统计信息
 */
export interface StorageStatistics {
  totalSize: number;                     // 总大小（字节）
  usedSize: number;                      // 已使用大小
  availableSize: number;                 // 可用大小
  items: StorageItem[];                  // 存储项列表
  lastUpdateTime: number;                // 最后更新时间
}

/**
 * 清理选项
 */
export interface ClearOptions {
  types: StorageType[];                  // 要清理的类型
  olderThan?: number;                    // 清理早于指定时间的文件（毫秒）
  keepRecent?: number;                   // 保留最近N个文件
}

/**
 * 清理结果
 */
export interface ClearResult {
  success: boolean;
  clearedSize: number;                   // 清理的大小（字节）
  clearedCount: number;                  // 清理的文件数
  errors: string[];                      // 错误信息
}

/**
 * 目录信息
 */
interface DirectoryInfo {
  size: number;
  count: number;
}

/**
 * 存储分析器类
 */
export class StorageAnalyzer {
  private static instance: StorageAnalyzer | null = null;
  private sandboxManager: SandboxManager;
  private imageCacheManager: ImageCacheManager;
  private databaseManager: DatabaseManager;
  private cachedStatistics: StorageStatistics | null = null;
  private lastAnalysisTime: number = 0;
  private readonly CACHE_DURATION = 30000; // 缓存30秒

  private constructor() {
    this.sandboxManager = SandboxManager.getInstance();
    this.imageCacheManager = ImageCacheManager.getInstance();
    this.databaseManager = DatabaseManager.getInstance();
  }

  public static getInstance(): StorageAnalyzer {
    if (!StorageAnalyzer.instance) {
      StorageAnalyzer.instance = new StorageAnalyzer();
    }
    return StorageAnalyzer.instance;
  }

  /**
   * 分析所有存储使用情况
   */
  public async analyzeStorage(forceRefresh: boolean = false): Promise<StorageStatistics> {
    try {
      const now = Date.now();
      
      // 如果有缓存且未过期，直接返回
      if (!forceRefresh && this.cachedStatistics && (now - this.lastAnalysisTime) < this.CACHE_DURATION) {
        logger.debug(TAG, '使用缓存的存储统计信息');
        return this.cachedStatistics;
      }

      logger.info(TAG, '开始分析存储使用情况...');
      
      // 【新增】尝试从系统API获取准确的存储信息
      await this.logSystemStorageInfo();
      
      const items: StorageItem[] = [];
      
      // === 应用沙箱目录 ===
      
      // 1. 分析图片内存缓存
      const imageCacheItem = await this.analyzeImageCache();
      items.push(imageCacheItem);
      
      // 2. 分析数据库
      const databaseItem = await this.analyzeDatabase();
      items.push(databaseItem);
      
      // 4. 分析漫画文件
      const comicFilesItem = await this.analyzeComicFiles();
      items.push(comicFilesItem);
      
      // 5. 分析封面文件
      const coverFilesItem = await this.analyzeCoverFiles();
      items.push(coverFilesItem);
      const libraryCoversItem = await this.analyzeLibraryCovers();
      items.push(libraryCoversItem);
      
      // 6. 分析章节文件
      const chapterFilesItem = await this.analyzeChapterFiles();
      items.push(chapterFilesItem);
      
      // 7. 分析临时文件
      const tempFilesItem = await this.analyzeTempFiles();
      items.push(tempFilesItem);
      
      // 8. 分析插件文件
      const pluginFilesItem = await this.analyzePluginFiles();
      items.push(pluginFilesItem);
      
      // 9. 分析永久图片缓存
      const permanentCacheItem = await this.analyzePermanentCache();
      items.push(permanentCacheItem);
      
      // 10. 分析电子书文件
      const ebookFilesItem = await this.analyzeEbookFiles();
      items.push(ebookFilesItem);
      
      // 11. 分析系统缓存目录
      const systemCacheItem = await this.analyzeSystemCache();
      items.push(systemCacheItem);
      
      // === Download文件夹目录 ===
      
      // 12. 分析Suwayomi封面缓存
      const suwayomiCoversItem = await this.analyzeSuwayomiCovers();
      items.push(suwayomiCoversItem);
      
      // 13. 分析Suwayomi图源图标缓存
      const suwayomiIconsItem = await this.analyzeSuwayomiSourceIcons();
      items.push(suwayomiIconsItem);
      
      // 14. 分析Suwayomi章节页面缓存
      const suwayomiChaptersItem = await this.analyzeSuwayomiChapters();
      items.push(suwayomiChaptersItem);

      const komgaCoversItem = await this.analyzeKomgaCovers();
      items.push(komgaCoversItem);

      const komgaChaptersItem = await this.analyzeKomgaChapters();
      items.push(komgaChaptersItem);
      
      // 15. 分析Download漫画文件
      const downloadMangaItem = await this.analyzeDownloadManga();
      items.push(downloadMangaItem);
      
      // 计算总大小
      const usedSize = items.reduce((sum, item) => sum + item.size, 0);
      
      const statistics: StorageStatistics = {
        totalSize: 0, // 暂时无法获取总存储空间
        usedSize: usedSize,
        availableSize: 0,
        items: items,
        lastUpdateTime: now
      };
      
      this.cachedStatistics = statistics;
      this.lastAnalysisTime = now;
      
      logger.info(TAG, `存储分析完成，总使用: ${this.formatSize(usedSize)}`);
      return statistics;
      
    } catch (error) {
      const err = error as Error;
      logger.error(TAG, `分析存储失败: ${err.message}`);
      throw err;
    }
  }

  /**
   * 分析图片缓存（仅内存缓存，磁盘缓存已合并到COVER_FILES）
   */
  private async analyzeImageCache(): Promise<StorageItem> {
    try {
      const cacheStats = await this.imageCacheManager.getCacheStats();
      const memorySize = cacheStats.memoryCache.size;
      
      return {
        type: StorageType.IMAGE_CACHE,
        name: '图片内存缓存',
        description: `临时缓存在内存中的图片`,
        size: memorySize,
        fileCount: cacheStats.memoryCache.count,
        path: '',
        canClear: true,
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析图片缓存失败: ${error}`);
      return this.createEmptyItem(StorageType.IMAGE_CACHE, '图片内存缓存');
    }
  }


  /**
   * 分析数据库
   */
  private async analyzeDatabase(): Promise<StorageItem> {
    try {
      // 【修复】使用实际的数据库目录路径
      const context = uiContextManager.getAbilityContext();
      if (!context) {
        logger.warn(TAG, 'Context未初始化，无法分析数据库');
        return this.createEmptyItem(StorageType.DATABASE, '数据库');
      }
      
      // 数据库文件实际存储在 context.databaseDir 下
      const dbPath = context.databaseDir;
      const dirInfo = await this.getDirectoryInfo(dbPath);
      const size = dirInfo.size;
      const count = dirInfo.count;
      
      logger.debug(TAG, `数据库路径: ${dbPath}, 大小: ${this.formatSize(size)}, 文件数: ${count}`);
      
      return {
        type: StorageType.DATABASE,
        name: '数据库',
        description: '漫画数据、阅读历史、收藏等',
        size: size,
        fileCount: count,
        path: dbPath,
        canClear: false, // 数据库不能随意清理
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析数据库失败: ${error}`);
      return this.createEmptyItem(StorageType.DATABASE, '数据库');
    }
  }

  /**
   * 分析漫画文件
   */
  private async analyzeComicFiles(): Promise<StorageItem> {
    try {
      const comicsPath = this.sandboxManager.getDirectory('comics');
      const dirInfo = await this.getDirectoryInfo(comicsPath);
      const size = dirInfo.size;
      const count = dirInfo.count;
      
      return {
        type: StorageType.COMIC_FILES,
        name: '漫画文件',
        description: '本地导入的漫画',
        size: size,
        fileCount: count,
        path: comicsPath,
        canClear: false, // 用户数据，不能自动清理
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析漫画文件失败: ${error}`);
      return this.createEmptyItem(StorageType.COMIC_FILES, '漫画文件');
    }
  }

  /**
   * 分析封面文件
   */
  private async analyzeCoverFiles(): Promise<StorageItem> {
    try {
      const coversPath = this.sandboxManager.getDirectory('covers');
      const dirInfo = await this.getDirectoryInfo(coversPath);
      const size = dirInfo.size;
      const count = dirInfo.count;
      
      return {
        type: StorageType.COVER_FILES,
        name: '封面文件',
        description: '漫画封面图片',
        size: size,
        fileCount: count,
        path: coversPath,
        canClear: true,
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析封面文件失败: ${error}`);
      return this.createEmptyItem(StorageType.COVER_FILES, '封面文件');
    }
  }

  /**
   * 分析章节文件
   */
  private async analyzeLibraryCovers(): Promise<StorageItem> {
    try {
      const context = uiContextManager.getAbilityContext();
      if (!context) {
        return this.createEmptyItem(StorageType.LIBRARY_COVERS, 'Library Covers');
      }
      const libraryCoverPath = `${context.filesDir}/library_covers`;
      const dirInfo = await this.getDirectoryInfo(libraryCoverPath);
      return {
        type: StorageType.LIBRARY_COVERS,
        name: 'Library Covers',
        description: 'Persistent cover files for library items',
        size: dirInfo.size,
        fileCount: dirInfo.count,
        path: libraryCoverPath,
        canClear: false,
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析书库封面失败: ${error}`);
      return this.createEmptyItem(StorageType.LIBRARY_COVERS, 'Library Covers');
    }
  }

  private async analyzeChapterFiles(): Promise<StorageItem> {
    try {
      const chaptersPath = this.sandboxManager.getDirectory('chapters');
      const dirInfo = await this.getDirectoryInfo(chaptersPath);
      const size = dirInfo.size;
      const count = dirInfo.count;
      
      return {
        type: StorageType.CHAPTER_FILES,
        name: '章节文件',
        description: '已下载的漫画章节',
        size: size,
        fileCount: count,
        path: chaptersPath,
        canClear: false, // 用户下载的内容
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析章节文件失败: ${error}`);
      return this.createEmptyItem(StorageType.CHAPTER_FILES, '章节文件');
    }
  }

  /**
   * 分析临时文件
   */
  private async analyzeTempFiles(): Promise<StorageItem> {
    try {
      const tempPath = this.sandboxManager.getDirectory('temp');
      const dirInfo = await this.getDirectoryInfo(tempPath);
      const size = dirInfo.size;
      const count = dirInfo.count;
      
      return {
        type: StorageType.TEMP_FILES,
        name: '临时文件',
        description: '临时缓存和处理文件',
        size: size,
        fileCount: count,
        path: tempPath,
        canClear: true,
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析临时文件失败: ${error}`);
      return this.createEmptyItem(StorageType.TEMP_FILES, '临时文件');
    }
  }

  /**
   * 分析插件文件
   */
  private async analyzePluginFiles(): Promise<StorageItem> {
    try {
      const pluginsPath = this.sandboxManager.getDirectory('plugins');
      const dirInfo = await this.getDirectoryInfo(pluginsPath);
      const size = dirInfo.size;
      const count = dirInfo.count;
      
      return {
        type: StorageType.PLUGIN_FILES,
        name: '插件文件',
        description: '图源插件和扩展',
        size: size,
        fileCount: count,
        path: pluginsPath,
        canClear: false, // 插件文件不能随意删除
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析插件文件失败: ${error}`);
      return this.createEmptyItem(StorageType.PLUGIN_FILES, '插件文件');
    }
  }

  /**
   * 分析永久图片缓存
   */
  private async analyzePermanentCache(): Promise<StorageItem> {
    try {
      const context = uiContextManager.getAbilityContext();
      if (!context) {
        logger.warn(TAG, 'Context未初始化，无法分析永久缓存');
        return this.createEmptyItem(StorageType.PERMANENT_CACHE, '永久图片缓存');
      }
      
      const permanentCachePath = context.filesDir + '/permanent_cache';
      const dirInfo = await this.getDirectoryInfo(permanentCachePath);
      const size = dirInfo.size;
      const count = dirInfo.count;
      
      return {
        type: StorageType.PERMANENT_CACHE,
        name: '永久图片缓存',
        description: '已下载漫画的图片缓存',
        size: size,
        fileCount: count,
        path: permanentCachePath,
        canClear: true,
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析永久缓存失败: ${error}`);
      return this.createEmptyItem(StorageType.PERMANENT_CACHE, '永久图片缓存');
    }
  }

  /**
   * 分析电子书文件
   */
  private async analyzeEbookFiles(): Promise<StorageItem> {
    try {
      const ebooksPath = this.sandboxManager.getDirectory('ebooks');
      const dirInfo = await this.getDirectoryInfo(ebooksPath);
      const size = dirInfo.size;
      const count = dirInfo.count;
      
      return {
        type: StorageType.EBOOK_FILES,
        name: '电子书文件',
        description: '下载的电子书',
        size: size,
        fileCount: count,
        path: ebooksPath,
        canClear: false, // 用户数据，不能自动清理
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析电子书文件失败: ${error}`);
      return this.createEmptyItem(StorageType.EBOOK_FILES, '电子书文件');
    }
  }

  /**
   * 分析系统缓存目录（context.cacheDir）
   */
  private async analyzeSystemCache(): Promise<StorageItem> {
    try {
      const context = uiContextManager.getAbilityContext();
      if (!context) {
        logger.warn(TAG, 'Context未初始化，无法分析系统缓存');
        return this.createEmptyItem(StorageType.SYSTEM_CACHE, '系统缓存');
      }
      
      // 系统缓存目录（包含所有cacheDir下的内容）
      const cachePath = context.cacheDir;
      const dirInfo = await this.getDirectoryInfo(cachePath);
      const size = dirInfo.size;
      const count = dirInfo.count;
      
      logger.debug(TAG, `系统缓存路径: ${cachePath}, 大小: ${this.formatSize(size)}, 文件数: ${count}`);
      
      return {
        type: StorageType.SYSTEM_CACHE,
        name: '系统缓存',
        description: '应用缓存目录（包含图片、WebView等缓存）',
        size: size,
        fileCount: count,
        path: cachePath,
        canClear: true,
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析系统缓存失败: ${error}`);
      return this.createEmptyItem(StorageType.SYSTEM_CACHE, '系统缓存');
    }
  }

  // ==================== Download文件夹分析方法 ====================

  /**
   * 获取Download目录下的子目录信息
   */
  private async getDownloadSubdirInfo(subPath: string): Promise<DirectoryInfo> {
    try {
      if (!DownloadDirManager.isReady()) {
        return { size: 0, count: 0 };
      }
      const basePath = DownloadDirManager.getPath();
      const fullPath = `${basePath}/${subPath}`;
      
      try {
        fs.accessSync(fullPath);
      } catch {
        return { size: 0, count: 0 };
      }
      
      return await this.calculateDirSize(fullPath);
    } catch (error) {
      logger.debug(TAG, `获取Download子目录信息失败: ${subPath}, ${error}`);
      return { size: 0, count: 0 };
    }
  }

  /**
   * 递归计算目录大小
   */
  private async calculateDirSize(dirPath: string): Promise<DirectoryInfo> {
    let totalSize = 0;
    let totalCount = 0;
    
    try {
      const entries = fs.listFileSync(dirPath);
      for (const entry of entries) {
        const fullPath = `${dirPath}/${entry}`;
        try {
          const stat = fs.statSync(fullPath);
          if (stat.isDirectory()) {
            const subInfo = await this.calculateDirSize(fullPath);
            totalSize += subInfo.size;
            totalCount += subInfo.count;
          } else {
            totalSize += stat.size;
            totalCount++;
          }
        } catch {
          // 忽略无法访问的文件
        }
      }
    } catch {
      // 目录不存在或无法访问
    }
    
    return { size: totalSize, count: totalCount };
  }

  /**
   * 分析Suwayomi封面缓存
   * 路径: /Download/com.dlzz.manxia/suwayomi/covers/
   */
  private async analyzeSuwayomiCovers(): Promise<StorageItem> {
    try {
      const dirInfo = await this.getDownloadSubdirInfo('suwayomi/covers');
      const basePath = DownloadDirManager.isReady() ? `${DownloadDirManager.getPath()}/suwayomi/covers` : '';
      
      return {
        type: StorageType.SUWAYOMI_COVERS,
        name: 'Suwayomi封面缓存',
        description: 'Suwayomi漫画封面图片缓存 (suwayomi/covers/)',
        size: dirInfo.size,
        fileCount: dirInfo.count,
        path: basePath,
        canClear: true,
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析Suwayomi封面缓存失败: ${error}`);
      return this.createEmptyItem(StorageType.SUWAYOMI_COVERS, 'Suwayomi封面缓存');
    }
  }

  /**
   * 分析Suwayomi图源图标缓存
   * 路径: /Download/com.dlzz.manxia/suwayomi/source_icons/
   */
  private async analyzeSuwayomiSourceIcons(): Promise<StorageItem> {
    try {
      const dirInfo = await this.getDownloadSubdirInfo('suwayomi/source_icons');
      const basePath = DownloadDirManager.isReady() ? `${DownloadDirManager.getPath()}/suwayomi/source_icons` : '';
      
      return {
        type: StorageType.SUWAYOMI_SOURCE_ICONS,
        name: 'Suwayomi图源图标',
        description: 'Suwayomi图源插件图标缓存 (suwayomi/source_icons/)',
        size: dirInfo.size,
        fileCount: dirInfo.count,
        path: basePath,
        canClear: true,
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析Suwayomi图源图标失败: ${error}`);
      return this.createEmptyItem(StorageType.SUWAYOMI_SOURCE_ICONS, 'Suwayomi图源图标');
    }
  }

  /**
   * 分析Suwayomi章节页面缓存
   * 路径: /Download/com.dlzz.manxia/suwayomi/chapters/
   */
  private async analyzeSuwayomiChapters(): Promise<StorageItem> {
    try {
      const dirInfo = await this.getDownloadSubdirInfo('suwayomi/chapters');
      const basePath = DownloadDirManager.isReady() ? `${DownloadDirManager.getPath()}/suwayomi/chapters` : '';
      
      return {
        type: StorageType.SUWAYOMI_CHAPTERS,
        name: 'Suwayomi章节缓存',
        description: 'Suwayomi漫画章节页面缓存 (suwayomi/chapters/)',
        size: dirInfo.size,
        fileCount: dirInfo.count,
        path: basePath,
        canClear: true,
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析Suwayomi章节缓存失败: ${error}`);
      return this.createEmptyItem(StorageType.SUWAYOMI_CHAPTERS, 'Suwayomi章节缓存');
    }
  }

  private async analyzeKomgaCovers(): Promise<StorageItem> {
    try {
      const context = uiContextManager.getAbilityContext();
      if (!context) {
        return this.createEmptyItem(StorageType.KOMGA_COVERS, 'Komga封面缓存');
      }

      const basePath = `${context.filesDir}/komga_cache/covers`;
      const dirInfo = await this.getDirectoryInfo(basePath);
      return {
        type: StorageType.KOMGA_COVERS,
        name: 'Komga封面缓存',
        description: 'Komga封面图片缓存 (filesDir/komga_cache/covers/)',
        size: dirInfo.size,
        fileCount: dirInfo.count,
        path: basePath,
        canClear: true,
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析Komga封面缓存失败: ${error}`);
      return this.createEmptyItem(StorageType.KOMGA_COVERS, 'Komga封面缓存');
    }
  }

  private async analyzeKomgaChapters(): Promise<StorageItem> {
    try {
      const context = uiContextManager.getAbilityContext();
      if (!context) {
        return this.createEmptyItem(StorageType.KOMGA_CHAPTERS, 'Komga章节缓存');
      }

      const basePath = `${context.filesDir}/komga_cache/chapters`;
      const dirInfo = await this.getDirectoryInfo(basePath);
      return {
        type: StorageType.KOMGA_CHAPTERS,
        name: 'Komga章节缓存',
        description: 'Komga章节页面缓存 (filesDir/komga_cache/chapters/)',
        size: dirInfo.size,
        fileCount: dirInfo.count,
        path: basePath,
        canClear: true,
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析Komga章节缓存失败: ${error}`);
      return this.createEmptyItem(StorageType.KOMGA_CHAPTERS, 'Komga章节缓存');
    }
  }

  /**
   * 分析Download漫画文件
   * 路径: /Download/com.dlzz.manxia/manga/
   */
  private async analyzeDownloadManga(): Promise<StorageItem> {
    try {
      const dirInfo = await this.getDownloadSubdirInfo('manga');
      const basePath = DownloadDirManager.isReady() ? `${DownloadDirManager.getPath()}/manga` : '';
      
      return {
        type: StorageType.DOWNLOAD_MANGA,
        name: '下载的漫画',
        description: '下载到Download文件夹的漫画 (manga/)',
        size: dirInfo.size,
        fileCount: dirInfo.count,
        path: basePath,
        canClear: false, // 用户下载的内容，不能自动清理
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析Download漫画失败: ${error}`);
      return this.createEmptyItem(StorageType.DOWNLOAD_MANGA, '下载的漫画');
    }
  }

  /**
   * 获取目录信息（大小和文件数）
   */
  private async getDirectoryInfo(dirPath: string): Promise<DirectoryInfo> {
    try {
      // 检查目录是否存在
      const exists = await this.sandboxManager.exists(dirPath);
      if (!exists) {
        logger.debug(TAG, `目录不存在: ${dirPath}`);
        return { size: 0, count: 0 };
      }
      
      const size = await this.sandboxManager.getDirectorySize(dirPath);
      const files = await this.sandboxManager.listDirectory(dirPath);
      const result: DirectoryInfo = { size: size, count: files.length };
      return result;
    } catch (error) {
      logger.debug(TAG, `获取目录信息失败: ${dirPath}, ${error}`);
      const emptyResult: DirectoryInfo = { size: 0, count: 0 };
      return emptyResult;
    }
  }

  /**
   * 【新增】记录系统存储信息（用于调试）
   */
  private async logSystemStorageInfo(): Promise<void> {
    try {
      const context = uiContextManager.getAbilityContext();
      if (!context) {
        return;
      }
      
      // 使用 storageStatistics API 获取应用存储信息
      storageStatistics.getCurrentBundleStats((err: BusinessError, bundleStats: storageStatistics.BundleStats) => {
        if (err) {
          logger.warn(TAG, `获取系统存储信息失败: code=${err.code}, message=${err.message}`);
          return;
        }
        
        logger.info(TAG, `=== 系统存储信息 ===`);
        logger.info(TAG, `应用总大小: ${this.formatSize(bundleStats.appSize)}`);
        logger.info(TAG, `缓存大小: ${this.formatSize(bundleStats.cacheSize)}`);
        logger.info(TAG, `数据大小: ${this.formatSize(bundleStats.dataSize)}`);
        logger.info(TAG, `==================`);
      });
      
      // 记录关键路径
      logger.debug(TAG, `filesDir: ${context.filesDir}`);
      logger.debug(TAG, `cacheDir: ${context.cacheDir}`);
      logger.debug(TAG, `databaseDir: ${context.databaseDir}`);
      logger.debug(TAG, `tempDir: ${context.tempDir}`);
      
    } catch (error) {
      logger.warn(TAG, `获取系统存储信息失败: ${error}`);
    }
  }

  /**
   * 创建空的存储项
   */
  private createEmptyItem(type: StorageType, name: string): StorageItem {
    return {
      type: type,
      name: name,
      description: '暂无数据',
      size: 0,
      fileCount: 0,
      path: '',
      canClear: false,
      lastModified: Date.now()
    };
  }

  /**
   * 清理存储
   */
  public async clearStorage(options: ClearOptions): Promise<ClearResult> {
    const result: ClearResult = {
      success: true,
      clearedSize: 0,
      clearedCount: 0,
      errors: []
    };

    try {
      logger.info(TAG, `开始清理存储，类型: ${options.types.join(', ')}`);

      for (const type of options.types) {
        try {
          const itemResult = await this.clearStorageItem(type, options);
          result.clearedSize += itemResult.clearedSize;
          result.clearedCount += itemResult.clearedCount;
        } catch (error) {
          result.errors.push(`清理${type}失败: ${error}`);
          result.success = false;
        }
      }

      // 清理后刷新统计
      this.cachedStatistics = null;
      await this.analyzeStorage(true);

      logger.info(TAG, `清理完成，清理大小: ${this.formatSize(result.clearedSize)}, 文件数: ${result.clearedCount}`);
      return result;

    } catch (error) {
      logger.error(TAG, `清理存储失败: ${error}`);
      result.success = false;
      result.errors.push(String(error));
      return result;
    }
  }

  /**
   * 清理单个存储项
   */
  private async clearStorageItem(type: StorageType, options: ClearOptions): Promise<ClearResult> {
    const result: ClearResult = {
      success: true,
      clearedSize: 0,
      clearedCount: 0,
      errors: []
    };

    switch (type) {
      case StorageType.IMAGE_CACHE:
        // 只清理内存缓存，磁盘文件由COVER_FILES管理
        const beforeStats = await this.imageCacheManager.getCacheStats();
        await this.imageCacheManager.clearMemoryCache();
        result.clearedSize = beforeStats.memoryCache.size;
        result.clearedCount = beforeStats.memoryCache.count;
        logger.info(TAG, `已清理内存缓存: ${this.formatSize(result.clearedSize)}`);
        break;

      case StorageType.COVER_FILES:
        const coversPath = this.sandboxManager.getDirectory('covers');
        const coverResult = await this.clearDirectory(coversPath, options);
        result.clearedSize = coverResult.clearedSize;
        result.clearedCount = coverResult.clearedCount;
        break;

      case StorageType.LIBRARY_COVERS:
        logger.info(TAG, '书库封面属于用户数据，不执行清理');
        break;

      case StorageType.TEMP_FILES:
        const tempPath = this.sandboxManager.getDirectory('temp');
        const tempResult = await this.clearDirectory(tempPath, options);
        result.clearedSize = tempResult.clearedSize;
        result.clearedCount = tempResult.clearedCount;
        break;

      case StorageType.PERMANENT_CACHE:
        const context1 = uiContextManager.getAbilityContext();
        if (context1) {
          const permanentCachePath = context1.filesDir + '/permanent_cache';
          const permanentResult = await this.clearDirectory(permanentCachePath, options);
          result.clearedSize = permanentResult.clearedSize;
          result.clearedCount = permanentResult.clearedCount;
        }
        break;

      case StorageType.SYSTEM_CACHE:
        const context2 = uiContextManager.getAbilityContext();
        if (context2) {
          const systemCachePath = context2.cacheDir;
          const systemCacheResult = await this.clearDirectory(systemCachePath, options);
          result.clearedSize = systemCacheResult.clearedSize;
          result.clearedCount = systemCacheResult.clearedCount;
        }
        break;

      // === Download文件夹清理 ===
      case StorageType.SUWAYOMI_COVERS:
        if (DownloadDirManager.isReady()) {
          const suwayomiCoversPath = `${DownloadDirManager.getPath()}/suwayomi/covers`;
          const coversResult = await this.clearDownloadDirectory(suwayomiCoversPath);
          result.clearedSize = coversResult.clearedSize;
          result.clearedCount = coversResult.clearedCount;
        }
        break;

      case StorageType.SUWAYOMI_SOURCE_ICONS:
        if (DownloadDirManager.isReady()) {
          const suwayomiIconsPath = `${DownloadDirManager.getPath()}/suwayomi/source_icons`;
          const iconsResult = await this.clearDownloadDirectory(suwayomiIconsPath);
          result.clearedSize = iconsResult.clearedSize;
          result.clearedCount = iconsResult.clearedCount;
        }
        break;

      case StorageType.SUWAYOMI_CHAPTERS:
        if (DownloadDirManager.isReady()) {
          const suwayomiChaptersPath = `${DownloadDirManager.getPath()}/suwayomi/chapters`;
          const chaptersResult = await this.clearDownloadDirectory(suwayomiChaptersPath);
          result.clearedSize = chaptersResult.clearedSize;
          result.clearedCount = chaptersResult.clearedCount;
        }
        break;

      case StorageType.KOMGA_COVERS:
        const context3 = uiContextManager.getAbilityContext();
        if (context3) {
          const komgaCoversPath = `${context3.filesDir}/komga_cache/covers`;
          const komgaCoversResult = await this.clearDirectory(komgaCoversPath, options);
          result.clearedSize = komgaCoversResult.clearedSize;
          result.clearedCount = komgaCoversResult.clearedCount;
        }
        break;

      case StorageType.KOMGA_CHAPTERS:
        const context4 = uiContextManager.getAbilityContext();
        if (context4) {
          const komgaChaptersPath = `${context4.filesDir}/komga_cache/chapters`;
          const komgaChaptersResult = await this.clearDirectory(komgaChaptersPath, options);
          result.clearedSize = komgaChaptersResult.clearedSize;
          result.clearedCount = komgaChaptersResult.clearedCount;
        }
        break;

      default:
        logger.warn(TAG, `不支持清理类型: ${type}`);
    }

    return result;
  }

  /**
   * 清理目录
   * [修复] 支持递归删除子目录
   */
  private async clearDirectory(dirPath: string, options: ClearOptions): Promise<ClearResult> {
    const result: ClearResult = {
      success: true,
      clearedSize: 0,
      clearedCount: 0,
      errors: []
    };

    try {
      const files = await this.sandboxManager.listDirectory(dirPath);
      const now = Date.now();

      for (const file of files) {
        try {
          const filePath = `${dirPath}/${file}`;
          const stat = await fileIo.stat(filePath);
          const shouldDelete = options.olderThan ? (now - stat.mtime) > options.olderThan : true;

          if (shouldDelete) {
            if (stat.isDirectory()) {
              // 递归删除子目录
              const subResult = await this.deleteDirectoryRecursive(filePath);
              result.clearedSize += subResult.size;
              result.clearedCount += subResult.count;
            } else {
              result.clearedSize += stat.size;
              await fileIo.unlink(filePath);
              result.clearedCount++;
            }
          }
        } catch (error) {
          result.errors.push(`删除失败: ${file}, ${error}`);
        }
      }
    } catch (error) {
      result.success = false;
      result.errors.push(`清理目录失败: ${dirPath}`);
    }

    return result;
  }

  /**
   * 递归删除目录及其所有内容
   */
  private async deleteDirectoryRecursive(dirPath: string): Promise<DeleteRecursiveResult> {
    let totalSize = 0;
    let totalCount = 0;

    try {
      const entries = await this.sandboxManager.listDirectory(dirPath);
      
      for (const entry of entries) {
        const fullPath = `${dirPath}/${entry}`;
        const stat = await fileIo.stat(fullPath);
        
        if (stat.isDirectory()) {
          const subResult = await this.deleteDirectoryRecursive(fullPath);
          totalSize += subResult.size;
          totalCount += subResult.count;
        } else {
          totalSize += stat.size;
          await fileIo.unlink(fullPath);
          totalCount++;
        }
      }
      
      // 删除空目录
      await fileIo.rmdir(dirPath);
      totalCount++;
      
    } catch (error) {
      logger.warn(TAG, `递归删除目录失败 ${dirPath}: ${error}`);
    }

    const result: DeleteRecursiveResult = { size: totalSize, count: totalCount };
    return result;
  }

  /**
   * 清理Download文件夹中的目录
   */
  private async clearDownloadDirectory(dirPath: string): Promise<ClearResult> {
    const result: ClearResult = {
      success: true,
      clearedSize: 0,
      clearedCount: 0,
      errors: []
    };

    try {
      try {
        fs.accessSync(dirPath);
      } catch {
        // 目录不存在，直接返回
        return result;
      }

      const entries = fs.listFileSync(dirPath);
      for (const entry of entries) {
        const fullPath = `${dirPath}/${entry}`;
        try {
          const stat = fs.statSync(fullPath);
          if (stat.isDirectory()) {
            const subResult = await this.deleteDownloadDirRecursive(fullPath);
            result.clearedSize += subResult.size;
            result.clearedCount += subResult.count;
          } else {
            result.clearedSize += stat.size;
            fs.unlinkSync(fullPath);
            result.clearedCount++;
          }
        } catch (error) {
          result.errors.push(`删除失败: ${entry}, ${error}`);
        }
      }
    } catch (error) {
      result.success = false;
      result.errors.push(`清理Download目录失败: ${dirPath}, ${error}`);
    }

    return result;
  }

  /**
   * 递归删除Download文件夹中的目录
   */
  private async deleteDownloadDirRecursive(dirPath: string): Promise<DeleteRecursiveResult> {
    let totalSize = 0;
    let totalCount = 0;

    try {
      const entries = fs.listFileSync(dirPath);
      for (const entry of entries) {
        const fullPath = `${dirPath}/${entry}`;
        try {
          const stat = fs.statSync(fullPath);
          if (stat.isDirectory()) {
            const subResult = await this.deleteDownloadDirRecursive(fullPath);
            totalSize += subResult.size;
            totalCount += subResult.count;
          } else {
            totalSize += stat.size;
            fs.unlinkSync(fullPath);
            totalCount++;
          }
        } catch {
          // 忽略无法删除的文件
        }
      }
      // 删除空目录
      fs.rmdirSync(dirPath);
      totalCount++;
    } catch {
      // 忽略错误
    }

    return { size: totalSize, count: totalCount };
  }

  /**
   * 格式化大小
   */
  public formatSize(bytes: number): string {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return (bytes / Math.pow(k, i)).toFixed(2) + ' ' + sizes[i];
  }

  /**
   * 计算百分比
   */
  public calculatePercentage(part: number, total: number): number {
    if (total === 0) return 0;
    return Math.round((part / total) * 100);
  }
}
