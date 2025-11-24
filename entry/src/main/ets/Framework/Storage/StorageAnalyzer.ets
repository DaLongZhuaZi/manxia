// 文件路径: src/main/ets/Framework/Storage/StorageAnalyzer.ets
/**
 * 存储分析器
 * 统一管理和分析应用的所有存储使用情况
 */

import { fileIo } from '@kit.CoreFileKit';
import { logger } from '../../Utils/Logger';
import { SandboxManager } from './SandboxManager';
import { ImageCacheManager } from '../Cache/ImageCacheManager';
import { WebViewDataCacheManager } from '../Cache/WebViewDataCacheManager';
import { DatabaseManager } from '../Database/DatabaseManager';

const TAG = 'StorageAnalyzer';

/**
 * 存储项类型
 */
export enum StorageType {
  IMAGE_CACHE = 'IMAGE_CACHE',           // 图片缓存
  WEBVIEW_CACHE = 'WEBVIEW_CACHE',       // WebView缓存
  DATABASE = 'DATABASE',                  // 数据库
  COMIC_FILES = 'COMIC_FILES',           // 漫画文件
  COVER_FILES = 'COVER_FILES',           // 封面文件
  CHAPTER_FILES = 'CHAPTER_FILES',       // 章节文件
  TEMP_FILES = 'TEMP_FILES',             // 临时文件
  PLUGIN_FILES = 'PLUGIN_FILES'          // 插件文件
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
  private webViewCacheManager: WebViewDataCacheManager;
  private databaseManager: DatabaseManager;
  private cachedStatistics: StorageStatistics | null = null;
  private lastAnalysisTime: number = 0;
  private readonly CACHE_DURATION = 30000; // 缓存30秒

  private constructor() {
    this.sandboxManager = SandboxManager.getInstance();
    this.imageCacheManager = ImageCacheManager.getInstance();
    this.webViewCacheManager = WebViewDataCacheManager.getInstance();
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
      
      const items: StorageItem[] = [];
      
      // 1. 分析图片缓存
      const imageCacheItem = await this.analyzeImageCache();
      items.push(imageCacheItem);
      
      // 2. 分析WebView缓存
      const webViewCacheItem = await this.analyzeWebViewCache();
      items.push(webViewCacheItem);
      
      // 3. 分析数据库
      const databaseItem = await this.analyzeDatabase();
      items.push(databaseItem);
      
      // 4. 分析漫画文件
      const comicFilesItem = await this.analyzeComicFiles();
      items.push(comicFilesItem);
      
      // 5. 分析封面文件
      const coverFilesItem = await this.analyzeCoverFiles();
      items.push(coverFilesItem);
      
      // 6. 分析章节文件
      const chapterFilesItem = await this.analyzeChapterFiles();
      items.push(chapterFilesItem);
      
      // 7. 分析临时文件
      const tempFilesItem = await this.analyzeTempFiles();
      items.push(tempFilesItem);
      
      // 8. 分析插件文件
      const pluginFilesItem = await this.analyzePluginFiles();
      items.push(pluginFilesItem);
      
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
   * 分析WebView缓存
   */
  private async analyzeWebViewCache(): Promise<StorageItem> {
    try {
      // WebView缓存在内存中，估算大小
      const estimatedSize = 10 * 1024 * 1024; // 估算10MB
      
      return {
        type: StorageType.WEBVIEW_CACHE,
        name: 'WebView缓存',
        description: '漫画详情和章节列表缓存',
        size: estimatedSize,
        fileCount: 0, // WebView缓存在内存中
        path: '',
        canClear: true,
        lastModified: Date.now()
      };
    } catch (error) {
      logger.error(TAG, `分析WebView缓存失败: ${error}`);
      return this.createEmptyItem(StorageType.WEBVIEW_CACHE, 'WebView缓存');
    }
  }

  /**
   * 分析数据库
   */
  private async analyzeDatabase(): Promise<StorageItem> {
    try {
      const dbPath = this.sandboxManager.getDirectory('database');
      const dirInfo = await this.getDirectoryInfo(dbPath);
      const size = dirInfo.size;
      const count = dirInfo.count;
      
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
   * 获取目录信息（大小和文件数）
   */
  private async getDirectoryInfo(dirPath: string): Promise<DirectoryInfo> {
    try {
      const size = await this.sandboxManager.getDirectorySize(dirPath);
      const files = await this.sandboxManager.listDirectory(dirPath);
      const result: DirectoryInfo = { size: size, count: files.length };
      return result;
    } catch (error) {
      const emptyResult: DirectoryInfo = { size: 0, count: 0 };
      return emptyResult;
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

      case StorageType.WEBVIEW_CACHE:
        // WebView缓存暂时无法清理
        logger.info(TAG, 'WebView缓存暂不支持清理');
        break;

      case StorageType.COVER_FILES:
        const coversPath = this.sandboxManager.getDirectory('covers');
        const coverResult = await this.clearDirectory(coversPath, options);
        result.clearedSize = coverResult.clearedSize;
        result.clearedCount = coverResult.clearedCount;
        break;

      case StorageType.TEMP_FILES:
        const tempPath = this.sandboxManager.getDirectory('temp');
        const tempResult = await this.clearDirectory(tempPath, options);
        result.clearedSize = tempResult.clearedSize;
        result.clearedCount = tempResult.clearedCount;
        break;

      default:
        logger.warn(TAG, `不支持清理类型: ${type}`);
    }

    return result;
  }

  /**
   * 清理目录
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
            result.clearedSize += stat.size;
            await fileIo.unlink(filePath);
            result.clearedCount++;
          }
        } catch (error) {
          result.errors.push(`删除文件失败: ${file}`);
        }
      }
    } catch (error) {
      result.success = false;
      result.errors.push(`清理目录失败: ${dirPath}`);
    }

    return result;
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
