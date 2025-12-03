/**
 * 封面缓存管理器
 * 负责管理漫画封面的本地缓存
 */

import { logger } from '../../Utils/Logger';
import { DatabaseManager } from '../Database/DatabaseManager';
import { TempMangaInfo, TempMangaDatabaseRecord } from '../../Models/TempMangaModels';
import { uiContextManager } from '../Managers/UIContextManager';
import fs from '@ohos.file.fs';
import http from '@ohos.net.http';
import { BusinessError } from '@ohos.base';

const TAG = 'CoverCacheManager';

/**
 * 封面统计信息接口
 */
export interface CoverStats {
  count: number;
  size: number;
}

export class CoverCacheManager {
  private static instance: CoverCacheManager;
  private dbManager: DatabaseManager;
  private coverBasePath: string = '';
  private downloadQueue: Map<string, Promise<string>> = new Map();
  private failedDownloads: Set<string> = new Set(); // 记录失败的下载，避免重复尝试
  private isPathInitialized: boolean = false;
  private initializationPromise: Promise<void> | null = null;
  private sourcePkgCache: Map<number, string> = new Map(); // sourceId -> pkg 缓存

  private constructor() {
    this.dbManager = DatabaseManager.getInstance();
    // 不在构造函数中初始化，延迟到首次使用时
  }

  public static getInstance(): CoverCacheManager {
    if (!CoverCacheManager.instance) {
      CoverCacheManager.instance = new CoverCacheManager();
    }
    return CoverCacheManager.instance;
  }

  /**
   * 初始化封面存储路径
   */
  private async initCoverPath(): Promise<void> {
    if (this.isPathInitialized) {
      return;
    }
    
    try {
      const context = uiContextManager.getAbilityContext();
      if (!context) {
        logger.warn(TAG, 'Context未初始化，延迟初始化封面路径');
        return;
      }
      
      this.coverBasePath = context.filesDir + '/covers';
      
      // 确保基础目录存在
      if (!fs.accessSync(this.coverBasePath)) {
        fs.mkdirSync(this.coverBasePath);
        logger.info(TAG, `创建封面基础目录: ${this.coverBasePath}`);
      }
      
      this.isPathInitialized = true;
      logger.info(TAG, `封面路径初始化完成: ${this.coverBasePath}`);
    } catch (error) {
      logger.error(TAG, `初始化封面路径失败: ${error}`);
      this.isPathInitialized = false;
    }
  }

  /**
   * 确保路径已初始化
   */
  private async ensurePathInitialized(): Promise<boolean> {
    if (this.isPathInitialized) {
      return true;
    }
    
    // 如果正在初始化，等待完成
    if (this.initializationPromise) {
      await this.initializationPromise;
      return this.isPathInitialized;
    }
    
    // 开始初始化
    this.initializationPromise = this.initCoverPath();
    await this.initializationPromise;
    this.initializationPromise = null;
    
    return this.isPathInitialized;
  }

  /**
   * 获取图源封面目录（使用pkg作为文件夹名，确保图源重装后缓存不丢失）
   */
  private getSourceCoverDir(sourceId: number): string {
    const pkg = this.sourcePkgCache.get(sourceId);
    if (pkg) {
      // 使用 pkg 作为目录名（清理特殊字符）
      const safePkg = pkg.replace(/[^a-zA-Z0-9._-]/g, '_');
      return `${this.coverBasePath}/${safePkg}`;
    }
    // 降级：使用 sourceId（仅在 pkg 未缓存时）
    return `${this.coverBasePath}/source_${sourceId}`;
  }
  
  /**
   * 确保图源的 pkg 已缓存
   */
  private async ensureSourcePkg(sourceId: number): Promise<string | null> {
    // 已缓存则直接返回
    if (this.sourcePkgCache.has(sourceId)) {
      return this.sourcePkgCache.get(sourceId) || null;
    }
    
    try {
      // 从数据库查询图源信息
      const sql = 'SELECT pkg FROM comic_source WHERE id = ?';
      const records = await this.dbManager.querySql(sql, [sourceId]);
      
      if (records && records.length > 0) {
        const record = records[0] as Record<string, Object>;
        const pkg = record.pkg as string;
        if (pkg && pkg.length > 0) {
          this.sourcePkgCache.set(sourceId, pkg);
          logger.debug(TAG, `缓存图源pkg: sourceId=${sourceId}, pkg=${pkg}`);
          return pkg;
        }
      }
    } catch (error) {
      logger.warn(TAG, `获取图源pkg失败: sourceId=${sourceId}, error=${error}`);
    }
    
    return null;
  }

  /**
   * 确保图源目录存在
   */
  private async ensureSourceDir(sourceId: number): Promise<boolean> {
    try {
      if (!await this.ensurePathInitialized()) {
        logger.error(TAG, '封面路径未初始化，无法创建图源目录');
        return false;
      }
      
      // 先确保 pkg 已缓存，这样 getSourceCoverDir 才能使用正确的目录名
      await this.ensureSourcePkg(sourceId);
      
      const dirPath = this.getSourceCoverDir(sourceId);
      if (!fs.accessSync(dirPath)) {
        fs.mkdirSync(dirPath);
        logger.debug(TAG, `创建图源目录: ${dirPath}`);
      }
      return true;
    } catch (error) {
      logger.error(TAG, `确保图源目录失败: ${error}`);
      return false;
    }
  }

  /**
   * 生成封面文件名
   */
  private generateCoverFileName(externalId: string, coverUrl: string): string {
    // 从URL提取扩展名
    let ext = '.jpg';
    const urlLower = coverUrl.toLowerCase();
    if (urlLower.includes('.png')) {
      ext = '.png';
    } else if (urlLower.includes('.webp')) {
      ext = '.webp';
    } else if (urlLower.includes('.jpeg')) {
      ext = '.jpeg';
    }
    
    // 使用externalId作为文件名（清理特殊字符）
    const safeId = externalId.replace(/[^a-zA-Z0-9_-]/g, '_');
    return `${safeId}${ext}`;
  }

  /**
   * 保存临时漫画信息（使用UPSERT减少查询）
   */
  async saveTempManga(
    sourceId: number,
    externalId: string,
    title: string,
    coverUrl: string
  ): Promise<void> {
    try {
      const id = `${sourceId}_${externalId}`;
      const now = Date.now();
      
      // 使用INSERT OR REPLACE减少一次查询
      const sql = `INSERT INTO temp_manga_info (id, sourceId, externalId, title, coverUrl, createTime, lastAccessTime) 
                   VALUES (?, ?, ?, ?, ?, ?, ?)
                   ON CONFLICT(id) DO UPDATE SET 
                     lastAccessTime = excluded.lastAccessTime,
                     title = excluded.title,
                     coverUrl = excluded.coverUrl`;
      await this.dbManager.executeSql(sql, [id, sourceId, externalId, title, coverUrl, now, now]);
      logger.debug(TAG, `保存临时漫画信息: ${title}`);
    } catch (error) {
      logger.error(TAG, `保存临时漫画信息失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 获取临时漫画信息
   */
  async getTempManga(sourceId: number, externalId: string): Promise<TempMangaInfo | null> {
    try {
      const id = `${sourceId}_${externalId}`;
      const sql = `SELECT * FROM temp_manga_info WHERE id = ?`;
      const records = await this.dbManager.querySql(sql, [id]);
      
      if (records && records.length > 0) {
        const record = records[0] as TempMangaDatabaseRecord;
        return {
          id: record.id,
          sourceId: record.sourceId,
          externalId: record.externalId,
          title: record.title,
          coverUrl: record.coverUrl,
          localCoverPath: record.localCoverPath || undefined,
          createTime: record.createTime,
          lastAccessTime: record.lastAccessTime
        };
      }
      return null;
    } catch (error) {
      logger.error(TAG, `获取临时漫画信息失败: ${error}`);
      return null;
    }
  }

  /**
   * 批量获取本地封面路径
   */
  async getBatchLocalCoverPaths(
    sourceId: number,
    externalIds: string[]
  ): Promise<Map<string, string | null>> {
    const result = new Map<string, string | null>();
    
    if (externalIds.length === 0) {
      return result;
    }
    
    try {
      // 批量查询数据库
      const placeholders = externalIds.map(() => '?').join(',');
      const ids = externalIds.map(id => `${sourceId}_${id}`);
      const sql = `SELECT * FROM temp_manga_info WHERE id IN (${placeholders})`;
      const records = await this.dbManager.querySql(sql, ids);
      
      // 构建映射
      const pathMap = new Map<string, string>();
      if (records && records.length > 0) {
        for (const record of records) {
          const tempManga = record as TempMangaDatabaseRecord;
          if (tempManga.localCoverPath) {
            pathMap.set(tempManga.externalId, tempManga.localCoverPath);
          }
        }
      }
      
      // 检查文件是否存在
      for (const externalId of externalIds) {
        const path = pathMap.get(externalId);
        if (path && fs.accessSync(path)) {
          result.set(externalId, path);
        } else {
          result.set(externalId, null);
          if (path) {
            // 文件不存在，异步清除记录（不阻塞）
            this.clearLocalCoverPath(sourceId, externalId).catch(() => {});
          }
        }
      }
    } catch (error) {
      logger.error(TAG, `批量获取本地封面路径失败: ${error}`);
      // 出错时返回空映射
      for (const externalId of externalIds) {
        result.set(externalId, null);
      }
    }
    
    return result;
  }

  /**
   * 获取本地封面路径（如果存在）
   */
  async getLocalCoverPath(sourceId: number, externalId: string): Promise<string | null> {
    try {
      const tempManga = await this.getTempManga(sourceId, externalId);
      if (tempManga && tempManga.localCoverPath) {
        // 检查文件是否存在
        if (fs.accessSync(tempManga.localCoverPath)) {
          return tempManga.localCoverPath;
        } else {
          // 文件不存在，清除数据库记录
          await this.clearLocalCoverPath(sourceId, externalId);
        }
      }
      return null;
    } catch (error) {
      logger.error(TAG, `获取本地封面路径失败: ${error}`);
      return null;
    }
  }

  /**
   * 清除本地封面路径记录
   */
  private async clearLocalCoverPath(sourceId: number, externalId: string): Promise<void> {
    try {
      const id = `${sourceId}_${externalId}`;
      const sql = `UPDATE temp_manga_info SET localCoverPath = NULL WHERE id = ?`;
      await this.dbManager.executeSql(sql, [id]);
    } catch (error) {
      logger.error(TAG, `清除本地封面路径失败: ${error}`);
    }
  }

  /**
   * 下载并缓存封面
   */
  async downloadAndCacheCover(
    sourceId: number,
    externalId: string,
    coverUrl: string,
    headers?: Record<string, string>
  ): Promise<string | null> {
    const cacheKey = `${sourceId}_${externalId}`;
    
    // 如果之前下载失败过，不再重试
    if (this.failedDownloads.has(cacheKey)) {
      logger.debug(TAG, `跳过已失败的封面: ${externalId}`);
      return null;
    }
    
    // 如果正在下载，返回现有的Promise
    const existingPromise = this.downloadQueue.get(cacheKey);
    if (existingPromise) {
      try {
        return await existingPromise;
      } catch (error) {
        return null;
      }
    }
    
    // 创建下载Promise
    const downloadPromise = this.doDownloadCover(sourceId, externalId, coverUrl, headers);
    this.downloadQueue.set(cacheKey, downloadPromise as Promise<string>);
    
    try {
      const result = await downloadPromise;
      if (!result) {
        // 下载失败，记录到失败集合
        this.failedDownloads.add(cacheKey);
      }
      return result;
    } finally {
      this.downloadQueue.delete(cacheKey);
    }
  }

  /**
   * 执行封面下载
   */
  private async doDownloadCover(
    sourceId: number,
    externalId: string,
    coverUrl: string,
    headers?: Record<string, string>
  ): Promise<string | null> {
    try {
      // 确保图源目录存在
      const dirReady = await this.ensureSourceDir(sourceId);
      if (!dirReady) {
        logger.error(TAG, '图源目录创建失败，无法下载封面');
        return null;
      }
      
      // 生成本地文件路径
      const fileName = this.generateCoverFileName(externalId, coverUrl);
      const localPath = `${this.getSourceCoverDir(sourceId)}/${fileName}`;
      
      // 如果文件已存在，直接返回
      if (fs.accessSync(localPath)) {
        logger.debug(TAG, `封面已存在: ${localPath}`);
        await this.updateLocalCoverPath(sourceId, externalId, localPath);
        return localPath;
      }
      
      // 下载封面
      logger.info(TAG, `开始下载封面: ${coverUrl}`);
      const httpRequest = http.createHttp();
      
      const requestOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers,
        readTimeout: 10000,  // 降低超时时间：10秒
        connectTimeout: 5000  // 降低连接超时：5秒
      };
      
      const response = await httpRequest.request(coverUrl, requestOptions);
      
      if (response.responseCode === 200) {
        // 保存文件
        const file = fs.openSync(localPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        if (typeof response.result === 'object' && response.result instanceof ArrayBuffer) {
          fs.writeSync(file.fd, response.result);
        }
        fs.closeSync(file);
        
        logger.info(TAG, `封面下载成功: ${localPath}`);
        
        // 更新数据库
        await this.updateLocalCoverPath(sourceId, externalId, localPath);
        
        httpRequest.destroy();
        return localPath;
      } else {
        logger.warn(TAG, `封面下载失败: HTTP ${response.responseCode}`);
        httpRequest.destroy();
        return null;
      }
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      const errCode = (error as Record<string, Object>)['code'];
      logger.error(TAG, `下载封面异常: message=${errMsg}, code=${errCode}, url=${coverUrl}`);
      return null;
    }
  }

  /**
   * 更新本地封面路径
   */
  private async updateLocalCoverPath(
    sourceId: number,
    externalId: string,
    localPath: string
  ): Promise<void> {
    try {
      const id = `${sourceId}_${externalId}`;
      
      // 先检查记录是否存在
      const existing = await this.getTempManga(sourceId, externalId);
      
      if (existing) {
        // 记录存在，更新路径
        const sql = `UPDATE temp_manga_info SET localCoverPath = ? WHERE id = ?`;
        await this.dbManager.executeSql(sql, [localPath, id]);
        logger.debug(TAG, `已更新封面路径: ${id}`);
      } else {
        // 记录不存在，说明saveTempManga还未执行，暂时不处理
        // 下次调用getLocalCoverPath时会检查文件是否存在
        logger.debug(TAG, `临时漫画记录不存在，跳过更新: ${id}`);
      }
    } catch (error) {
      logger.error(TAG, `更新本地封面路径失败: ${error}`);
    }
  }

  /**
   * 清理过期封面
   * @param daysToKeep 保留天数
   * @returns 清理的文件数量
   */
  async cleanupExpiredCovers(daysToKeep: number = 30): Promise<number> {
    try {
      const cutoffTime = Date.now() - (daysToKeep * 24 * 60 * 60 * 1000);
      const sql = `SELECT * FROM temp_manga_info WHERE lastAccessTime < ? AND localCoverPath IS NOT NULL`;
      const records = await this.dbManager.querySql(sql, [cutoffTime]);
      
      let cleanedCount = 0;
      
      if (records && records.length > 0) {
        for (const record of records) {
          const tempManga = record as TempMangaDatabaseRecord;
          if (tempManga.localCoverPath) {
            try {
              if (fs.accessSync(tempManga.localCoverPath)) {
                fs.unlinkSync(tempManga.localCoverPath);
                cleanedCount++;
              }
              await this.clearLocalCoverPath(tempManga.sourceId, tempManga.externalId);
            } catch (error) {
              logger.warn(TAG, `删除封面文件失败: ${tempManga.localCoverPath}`);
            }
          }
        }
      }
      
      logger.info(TAG, `清理过期封面完成: 删除${cleanedCount}个文件`);
      return cleanedCount;
    } catch (error) {
      logger.error(TAG, `清理过期封面失败: ${error}`);
      return 0;
    }
  }

  /**
   * 获取图源封面统计信息（统计新旧两种格式的目录）
   */
  async getSourceCoverStats(sourceId: number): Promise<CoverStats> {
    try {
      if (!await this.ensurePathInitialized()) {
        const emptyStats: CoverStats = { count: 0, size: 0 };
        return emptyStats;
      }
      
      // 先确保 pkg 已缓存
      const pkg = await this.ensureSourcePkg(sourceId);
      
      let totalCount = 0;
      let totalSize = 0;
      
      // 统计新格式目录（基于 pkg）
      if (pkg) {
        const safePkg = pkg.replace(/[^a-zA-Z0-9._-]/g, '_');
        const pkgPath = `${this.coverBasePath}/${safePkg}`;
        if (fs.accessSync(pkgPath)) {
          const stat = this.countDirectoryStats(pkgPath);
          totalCount += stat.count;
          totalSize += stat.size;
        }
      }
      
      // 统计旧格式目录（基于 sourceId）- 兼容旧数据
      const oldPath = `${this.coverBasePath}/source_${sourceId}`;
      if (fs.accessSync(oldPath)) {
        const stat = this.countDirectoryStats(oldPath);
        totalCount += stat.count;
        totalSize += stat.size;
      }
      
      const result: CoverStats = { count: totalCount, size: totalSize };
      return result;
    } catch (error) {
      logger.error(TAG, `获取图源封面统计失败: ${error}`);
      const emptyStats: CoverStats = { count: 0, size: 0 };
      return emptyStats;
    }
  }
  
  /**
   * 计算目录统计信息
   */
  private countDirectoryStats(dirPath: string): CoverStats {
    try {
      const files = fs.listFileSync(dirPath);
      let totalSize = 0;
      
      for (const fileName of files) {
        const filePath = `${dirPath}/${fileName}`;
        try {
          const stat = fs.statSync(filePath);
          totalSize += stat.size;
        } catch (error) {
          // 忽略错误
        }
      }
      
      const result: CoverStats = { count: files.length, size: totalSize };
      return result;
    } catch (error) {
      const emptyStats: CoverStats = { count: 0, size: 0 };
      return emptyStats;
    }
  }

  /**
   * 删除图源所有封面（删除新旧两种格式的目录）
   */
  async deleteSourceCovers(sourceId: number): Promise<number> {
    try {
      if (!await this.ensurePathInitialized()) {
        logger.warn(TAG, '封面路径未初始化，无法删除封面');
        return 0;
      }
      
      // 先确保 pkg 已缓存
      const pkg = await this.ensureSourcePkg(sourceId);
      let deletedCount = 0;
      
      // 删除新格式目录（基于 pkg）
      if (pkg) {
        const safePkg = pkg.replace(/[^a-zA-Z0-9._-]/g, '_');
        const pkgPath = `${this.coverBasePath}/${safePkg}`;
        if (fs.accessSync(pkgPath)) {
          deletedCount += this.deleteFilesInDirectory(pkgPath);
        }
      }
      
      // 删除旧格式目录（基于 sourceId）- 兼容旧数据
      const oldPath = `${this.coverBasePath}/source_${sourceId}`;
      if (fs.accessSync(oldPath)) {
        deletedCount += this.deleteFilesInDirectory(oldPath);
      }
      
      // 清除数据库记录
      const sql = `UPDATE temp_manga_info SET localCoverPath = NULL WHERE sourceId = ?`;
      await this.dbManager.executeSql(sql, [sourceId]);
      
      logger.info(TAG, `删除图源封面完成: sourceId=${sourceId}, 删除${deletedCount}个文件`);
      return deletedCount;
    } catch (error) {
      logger.error(TAG, `删除图源封面失败: ${error}`);
      return 0;
    }
  }
  
  /**
   * 删除目录中的所有文件并返回删除数量
   */
  private deleteFilesInDirectory(dirPath: string): number {
    try {
      const files = fs.listFileSync(dirPath);
      let deletedCount = 0;
      
      for (const fileName of files) {
        const filePath = `${dirPath}/${fileName}`;
        try {
          fs.unlinkSync(filePath);
          deletedCount++;
        } catch (error) {
          logger.warn(TAG, `删除封面文件失败: ${filePath}`);
        }
      }
      return deletedCount;
    } catch (error) {
      return 0;
    }
  }

  /**
   * 获取所有图源的封面统计
   */
  async getAllSourceCoverStats(): Promise<Map<number, CoverStats>> {
    const stats = new Map<number, CoverStats>();
    
    try {
      if (!await this.ensurePathInitialized()) {
        return stats;
      }
      
      if (!fs.accessSync(this.coverBasePath)) {
        return stats;
      }
      
      // 先从数据库获取所有图源的 id 和 pkg 映射
      const pkgToIdMap = new Map<string, number>();
      try {
        const sql = 'SELECT id, pkg FROM comic_source WHERE pkg IS NOT NULL';
        const records = await this.dbManager.querySql(sql, []);
        if (records) {
          for (const record of records) {
            const r = record as Record<string, Object>;
            const pkg = r.pkg as string;
            const id = Number(r.id);
            if (pkg && !isNaN(id)) {
              const safePkg = pkg.replace(/[^a-zA-Z0-9._-]/g, '_');
              pkgToIdMap.set(safePkg, id);
            }
          }
        }
      } catch (dbError) {
        logger.warn(TAG, `获取图源映射失败: ${dbError}`);
      }
      
      const dirs = fs.listFileSync(this.coverBasePath);
      
      for (const dirName of dirs) {
        let sourceId: number | undefined;
        
        // 旧格式: source_X
        if (dirName.startsWith('source_')) {
          sourceId = parseInt(dirName.replace('source_', ''));
        }
        // 新格式: pkg (如 com.manxia.extension.zh.pixiv)
        else if (pkgToIdMap.has(dirName)) {
          sourceId = pkgToIdMap.get(dirName);
        }
        
        if (sourceId !== undefined && !isNaN(sourceId)) {
          const stat = await this.getSourceCoverStats(sourceId);
          // 合并同一 sourceId 的统计（可能同时存在新旧格式）
          const existing = stats.get(sourceId);
          if (existing) {
            stats.set(sourceId, {
              count: existing.count + stat.count,
              size: existing.size + stat.size
            });
          } else {
            stats.set(sourceId, stat);
          }
        }
      }
    } catch (error) {
      logger.error(TAG, `获取所有图源封面统计失败: ${error}`);
    }
    
    return stats;
  }

  /**
   * 清理指定图源的所有封面
   */
  async cleanSourceCovers(sourceId: number): Promise<void> {
    try {
      if (!await this.ensurePathInitialized()) {
        logger.error(TAG, '封面路径未初始化，无法清理封面');
        return;
      }
      
      // 先确保 pkg 已缓存
      const pkg = await this.ensureSourcePkg(sourceId);
      
      // 删除新格式目录（基于 pkg）
      if (pkg) {
        const safePkg = pkg.replace(/[^a-zA-Z0-9._-]/g, '_');
        const pkgPath = `${this.coverBasePath}/${safePkg}`;
        if (fs.accessSync(pkgPath)) {
          this.deleteDirectory(pkgPath);
          logger.info(TAG, `已删除图源封面(pkg格式): ${pkgPath}`);
        }
      }
      
      // 删除旧格式目录（基于 sourceId）- 兼容旧数据
      const sourcePath = `${this.coverBasePath}/source_${sourceId}`;
      if (fs.accessSync(sourcePath)) {
        this.deleteDirectory(sourcePath);
        logger.info(TAG, `已删除图源封面(旧格式): ${sourcePath}`);
      }
      
      // 清理数据库记录
      const dbManager = DatabaseManager.getInstance();
      await dbManager.executeSql(
        'DELETE FROM temp_manga_info WHERE sourceId = ?',
        [sourceId]
      );
    } catch (error) {
      const errorMsg = `删除图源封面失败: ${error}`;
      logger.error(TAG, errorMsg);
      throw new Error(errorMsg);
    }
  }

  /**
   * 递归删除目录
   */
  private deleteDirectory(dirPath: string): void {
    try {
      if (!fs.accessSync(dirPath)) {
        return;
      }

      const files = fs.listFileSync(dirPath);
      for (const file of files) {
        const filePath = `${dirPath}/${file}`;
        const stat = fs.statSync(filePath);
        
        if (stat.isDirectory()) {
          this.deleteDirectory(filePath);
        } else {
          fs.unlinkSync(filePath);
        }
      }
      
      fs.rmdirSync(dirPath);
    } catch (error) {
      logger.error(TAG, `删除目录失败: ${dirPath}, ${error}`);
    }
  }
}
