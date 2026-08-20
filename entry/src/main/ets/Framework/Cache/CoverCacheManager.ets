import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
/**
 * 封面缓存管理器
 * 负责管理漫画封面的本地缓存
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { DatabaseManager } from 'manxia_core/src/main/ets/Framework/Database/DatabaseManager';
import { TempMangaInfo, TempMangaDatabaseRecord } from 'manxia_core/src/main/ets/Models/TempMangaModels';
import { uiContextManager } from '../Managers/UIContextManager';
import CookieManager from '../Managers/CookieManager';
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

interface CoverCacheRecord {
  localPath?: string;
  referer?: string;
}

export class CoverCacheManager {
  private static instance: CoverCacheManager;
  private dbManager: DatabaseManager;

  private coverBasePath: string = '';
  private downloadQueue: Map<string, Promise<string>> = new Map();
  private failedDownloads: Map<string, number> = new Map(); // 记录失败时间，避免短时间重复尝试
  private readonly failedDownloadTtlMs: number = 30 * 60 * 1000;
  private readonly maxFailedDownloadRecords: number = 500;
  private isPathInitialized: boolean = false;
  private initializationPromise: Promise<void> | null = null;
  private pendingContextLogged: boolean = false;
  private sourcePkgCache: Map<number, string> = new Map(); // sourceId -> pkg 缓存
  private readonly photos18Pkg: string = 'com.manxia.extension.all.photos18';
  private photos18CoverRecords: Map<string, CoverCacheRecord> = new Map();


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

  private isFailedDownloadFresh(cacheKey: string): boolean {
    const failedAt = this.failedDownloads.get(cacheKey);
    if (!failedAt) {
      return false;
    }
    if (Date.now() - failedAt <= this.failedDownloadTtlMs) {
      return true;
    }
    this.failedDownloads.delete(cacheKey);
    return false;
  }

  private recordFailedDownload(cacheKey: string): void {
    this.failedDownloads.set(cacheKey, Date.now());
    this.trimFailedDownloadRecords();
  }

  private clearFailedDownload(cacheKey: string): void {
    this.failedDownloads.delete(cacheKey);
  }

  private trimFailedDownloadRecords(): void {
    const now = Date.now();
    const expiredKeys: string[] = [];
    this.failedDownloads.forEach((failedAt: number, cacheKey: string) => {
      if (now - failedAt > this.failedDownloadTtlMs) {
        expiredKeys.push(cacheKey);
      }
    });
    for (const cacheKey of expiredKeys) {
      this.failedDownloads.delete(cacheKey);
    }

    while (this.failedDownloads.size > this.maxFailedDownloadRecords) {
      let oldestKey: string = '';
      let oldestTime: number = 9007199254740991;
      this.failedDownloads.forEach((failedAt: number, cacheKey: string) => {
        if (failedAt < oldestTime) {
          oldestTime = failedAt;
          oldestKey = cacheKey;
        }
      });
      if (oldestKey.length === 0) {
        break;
      }
      this.failedDownloads.delete(oldestKey);
    }
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
        if (!this.pendingContextLogged) {
          logger.debug(TAG, 'Context未初始化，封面路径等待后续按需初始化');
          this.pendingContextLogged = true;
        }
        return;
      }
      
      this.coverBasePath = context.filesDir + '/covers';
      this.pendingContextLogged = false;
      
      // 确保基础目录存在
      if (!SafeFileUtils.accessSync(this.coverBasePath)) {
        SafeFileUtils.mkdirSync(this.coverBasePath);
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
      if (!SafeFileUtils.accessSync(dirPath)) {
        SafeFileUtils.mkdirSync(dirPath);
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
        if (path && SafeFileUtils.accessSync(path)) {
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
    return this.getLocalCoverPathWithReferer(sourceId, externalId, '');
  }

  async getLocalCoverPathWithReferer(sourceId: number, externalId: string, referer: string): Promise<string | null> {
    try {
      const isPhotos18 = await this.isPhotos18Source(sourceId);
      const normalizedReferer = referer && referer.length > 0 ? referer : '';
      const recordKey = this.getCoverRecordKey(sourceId, externalId);
      if (isPhotos18) {
        const cachedRecord = this.photos18CoverRecords.get(recordKey);
        if (cachedRecord && cachedRecord.localPath && SafeFileUtils.accessSync(cachedRecord.localPath)) {
          if (!cachedRecord.referer || cachedRecord.referer === normalizedReferer || normalizedReferer.length === 0) {
            return cachedRecord.localPath;
          }
        }
      }
      const tempManga = await this.getTempManga(sourceId, externalId);
      if (tempManga && tempManga.localCoverPath) {
        // 检查文件是否存在
        if (SafeFileUtils.accessSync(tempManga.localCoverPath)) {
          if (isPhotos18) {
            const cacheRecord: CoverCacheRecord = {
              localPath: tempManga.localCoverPath,
              referer: normalizedReferer
            };
            this.photos18CoverRecords.set(recordKey, cacheRecord);
            if (normalizedReferer.length > 0) {
              const expectedPartition = this.buildPhotos18CoverPartition(externalId, normalizedReferer);
              if (tempManga.localCoverPath.indexOf(expectedPartition) < 0) {
                return null;
              }
            }
          }
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

  private async isPhotos18Source(sourceId: number): Promise<boolean> {
    const pkg: string | null = await this.ensureSourcePkg(sourceId);
    if (!pkg) {
      return false;
    }
    return pkg === this.photos18Pkg;
  }

  private getCoverRecordKey(sourceId: number, externalId: string): string {
    return `${sourceId}_${externalId}`;
  }

  private sanitizePartition(value: string): string {
    return value.replace(/[^a-zA-Z0-9_-]/g, '_');
  }

  private buildPhotos18CoverPartition(externalId: string, referer: string): string {
    const safeExternalId = this.sanitizePartition(externalId);
    if (!referer || referer.length === 0) {
      return `photos18_cover_${safeExternalId}`;
    }
    let hash = 0;
    for (let i = 0; i < referer.length; i++) {
      const char = referer.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash;
    }
    return `photos18_cover_${safeExternalId}_${Math.abs(hash).toString(36)}`;
  }

  private resolvePhotos18Referer(headers?: Record<string, string>): string {
    if (!headers) {
      return '';
    }
    if (headers['X-Cache-Referer'] && headers['X-Cache-Referer'].length > 0) {
      return headers['X-Cache-Referer'];
    }
    if (headers['Referer'] && headers['Referer'].length > 0) {
      return headers['Referer'];
    }
    return '';
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
    const isPhotos18 = await this.isPhotos18Source(sourceId);
    const referer = this.resolvePhotos18Referer(headers);
    const cacheKey = isPhotos18 ? `${sourceId}_${externalId}_${referer}` : `${sourceId}_${externalId}`;
    
    // 如果短时间内下载失败过，不再重试；过期后允许恢复
    if (this.isFailedDownloadFresh(cacheKey)) {
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
        if (!isPhotos18) {
          // 下载失败，记录到失败集合
          this.recordFailedDownload(cacheKey);
        } else {
          logger.warn(TAG, `Photos18封面下载失败，不写入失败黑名单: ${externalId}`);
        }
      } else {
        this.clearFailedDownload(cacheKey);
        if (isPhotos18) {
          const recordKey = this.getCoverRecordKey(sourceId, externalId);
          this.photos18CoverRecords.set(recordKey, {
            localPath: result,
            referer: referer
          });
        }
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
      const isPhotos18 = await this.isPhotos18Source(sourceId);
      const referer = this.resolvePhotos18Referer(headers);
      let fileName = this.generateCoverFileName(externalId, coverUrl);
      if (isPhotos18) {
        const partition = this.buildPhotos18CoverPartition(externalId, referer);
        fileName = `${partition}${fileName.substring(fileName.lastIndexOf('.'))}`;
      }
      const localPath = `${this.getSourceCoverDir(sourceId)}/${fileName}`;

      
      // 如果文件已存在，直接返回
      if (SafeFileUtils.accessSync(localPath)) {
        logger.debug(TAG, `封面已存在: ${localPath}`);
        await this.updateLocalCoverPath(sourceId, externalId, localPath);
        return localPath;
      }
      
      // 下载封面（支持SSL错误时自动降级为HTTP）
      logger.info(TAG, `开始下载封面: ${coverUrl}`);

      
      // 构建请求头，添加Referer和User-Agent以解决防盗链和SSL问题
      const finalHeaders: Record<string, string> = {};
      finalHeaders['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      finalHeaders['Accept'] = 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8';
      finalHeaders['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.8';
      
      // 合并传入的headers
      if (headers) {
        const headerKeys = Object.keys(headers);
        for (let i = 0; i < headerKeys.length; i++) {
          const key = headerKeys[i];
          if (key === 'X-Cache-Referer' || key === 'X-Cache-Partition') {
            continue;
          }
          finalHeaders[key] = headers[key];
        }
      }

      if (isPhotos18) {
        try {
          const preciseCookie: string = await CookieManager.getInstance().getCookieStringForUrl(sourceId, coverUrl);
          if (preciseCookie.length > 0) {
            finalHeaders['Cookie'] = preciseCookie;
            logger.debug(TAG, `Photos18封面按URL刷新Cookie成功: sourceId=${sourceId}, length=${preciseCookie.length}`);
          }
        } catch (cookieError) {
          logger.warn(TAG, `Photos18封面按URL刷新Cookie失败: sourceId=${sourceId}, error=${String(cookieError)}`);
        }
      }

      
      // 根据图片URL自动添加Referer（解决防盗链问题）
      if (coverUrl.includes('amh1234.wszwhg.net') || coverUrl.includes('gmh1234.wszwhg.net')) {
        finalHeaders['Referer'] = 'https://b.amh1234.com/';
        finalHeaders['Origin'] = 'https://b.amh1234.com';
      }

      // Pixiv CDN防盗链
      if (coverUrl.includes('i.pximg.net') || coverUrl.includes('.pximg.net')) {
        if (!finalHeaders['Referer']) {
          finalHeaders['Referer'] = 'https://www.pixiv.net/';
        }
        if (!finalHeaders['Origin']) {
          finalHeaders['Origin'] = 'https://www.pixiv.net';
        }
      }

      if (coverUrl.includes('dogemanga.com/images/')) {
        finalHeaders['Referer'] = 'https://dogemanga.com/';
        finalHeaders['Origin'] = 'https://dogemanga.com';
      }
      
      // 尝试下载，如果SSL错误则降级为HTTP
      // result: [success, sslError]
      let downloadUrl = coverUrl;
      let result = await this.tryDownloadCover(downloadUrl, finalHeaders, localPath);

      if (!result[0] && isPhotos18) {
        logger.warn(TAG, `Photos18封面下载失败，允许后续重新尝试: ${coverUrl}`);
      }
      
      // 如果SSL错误且是HTTPS，尝试HTTP降级
      if (result[1] && downloadUrl.startsWith('https://')) {
        downloadUrl = downloadUrl.replace('https://', 'http://');
        logger.info(TAG, `SSL错误，尝试HTTP降级: ${downloadUrl}`);
        result = await this.tryDownloadCover(downloadUrl, finalHeaders, localPath);
      }
      
      if (result[0]) {
        // 更新数据库
        await this.updateLocalCoverPath(sourceId, externalId, localPath);
        return localPath;
      } else {
        return null;
      }
    } catch (error) {
      let errMsg: string = '';
      if (error instanceof Error) {
        errMsg = error.message;
      } else if (typeof error === 'object' && error !== null) {
        const msg = (error as Record<string, Object>)['message'];
        if (typeof msg === 'string') {
          errMsg = msg;
        } else if (msg !== undefined && msg !== null) {
          try { errMsg = JSON.stringify(msg); } catch (_e) { errMsg = String(msg); }
        } else {
          try { errMsg = JSON.stringify(error); } catch (_e2) { errMsg = String(error); }
        }
      } else {
        errMsg = String(error);
      }
      const errCode = (error as Record<string, Object>)['code'];
      logger.error(TAG, `下载封面异常: message=${errMsg}, code=${errCode}, url=${coverUrl}`);
      return null;
    }
  }

  /**
   * 尝试下载封面（内部方法）
   * @returns [success, sslError] - 下载是否成功，是否是SSL错误
   */
  private async tryDownloadCover(
    url: string,
    headers: Record<string, string>,
    localPath: string
  ): Promise<boolean[]> {
    try {
      const httpRequest = http.createHttp();
      
      const requestOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers,
        readTimeout: 10000,
        connectTimeout: 5000
      };
      
      const response = await httpRequest.request(url, requestOptions);
      
      if (response.responseCode === 200) {
        // 保存文件
        const file = SafeFileUtils.openSync(localPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        if (typeof response.result === 'object' && response.result instanceof ArrayBuffer) {
          SafeFileUtils.writeSync(file.fd, response.result);
        }
        SafeFileUtils.closeSync(file);
        
        logger.info(TAG, `封面下载成功: ${localPath}`);
        httpRequest.destroy();
        return [true, false];  // success=true, sslError=false
      } else {
        logger.warn(TAG, `封面下载失败: HTTP ${response.responseCode}`);
        httpRequest.destroy();
        return [false, false];  // success=false, sslError=false
      }
    } catch (error) {
      const errObj = error as Object;
      const errCode = (errObj as Record<string, Object>)['code'];
      let errMsg: string = '';
      if (error instanceof Error) {
        errMsg = error.message;
      } else if (typeof error === 'object' && error !== null) {
        const msg = (errObj as Record<string, Object>)['message'];
        if (typeof msg === 'string') {
          errMsg = msg;
        } else if (msg !== undefined && msg !== null) {
          try { errMsg = JSON.stringify(msg); } catch (_e) { errMsg = String(msg); }
        } else {
          try { errMsg = JSON.stringify(error); } catch (_e2) { errMsg = String(error); }
        }
      } else {
        errMsg = String(error);
      }

      // 检查是否是SSL错误 (code=2300060)
      const isSslError = errCode === 2300060;

      if (isSslError) {
        logger.warn(TAG, `封面下载SSL错误: ${url}`);
      } else {
        logger.error(TAG, `封面下载异常: message=${errMsg}, code=${errCode}, url=${url}`);
      }

      return [false, isSslError];  // success=false, sslError=isSslError
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
              if (SafeFileUtils.accessSync(tempManga.localCoverPath)) {
                SafeFileUtils.unlinkSync(tempManga.localCoverPath);
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
        if (SafeFileUtils.accessSync(pkgPath)) {
          const stat = this.countDirectoryStats(pkgPath);
          totalCount += stat.count;
          totalSize += stat.size;
        }
      }
      
      // 统计旧格式目录（基于 sourceId）- 兼容旧数据
      const oldPath = `${this.coverBasePath}/source_${sourceId}`;
      if (SafeFileUtils.accessSync(oldPath)) {
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
      const files = SafeFileUtils.listFileSync(dirPath);
      let totalSize = 0;
      
      for (const fileName of files) {
        const filePath = `${dirPath}/${fileName}`;
        try {
          const stat = SafeFileUtils.statSync(filePath);
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
        if (SafeFileUtils.accessSync(pkgPath)) {
          deletedCount += this.deleteFilesInDirectory(pkgPath);
        }
      }
      
      // 删除旧格式目录（基于 sourceId）- 兼容旧数据
      const oldPath = `${this.coverBasePath}/source_${sourceId}`;
      if (SafeFileUtils.accessSync(oldPath)) {
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
      const files = SafeFileUtils.listFileSync(dirPath);
      let deletedCount = 0;
      
      for (const fileName of files) {
        const filePath = `${dirPath}/${fileName}`;
        try {
          SafeFileUtils.unlinkSync(filePath);
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
      
      if (!SafeFileUtils.accessSync(this.coverBasePath)) {
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
      
      const dirs = SafeFileUtils.listFileSync(this.coverBasePath);
      
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
        if (SafeFileUtils.accessSync(pkgPath)) {
          this.deleteDirectory(pkgPath);
          logger.info(TAG, `已删除图源封面(pkg格式): ${pkgPath}`);
        }
      }
      
      // 删除旧格式目录（基于 sourceId）- 兼容旧数据
      const sourcePath = `${this.coverBasePath}/source_${sourceId}`;
      if (SafeFileUtils.accessSync(sourcePath)) {
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
      if (!SafeFileUtils.accessSync(dirPath)) {
        return;
      }

      const files = SafeFileUtils.listFileSync(dirPath);
      for (const file of files) {
        const filePath = `${dirPath}/${file}`;
        const stat = SafeFileUtils.statSync(filePath);
        
        if (stat.isDirectory()) {
          this.deleteDirectory(filePath);
        } else {
          SafeFileUtils.unlinkSync(filePath);
        }
      }
      
      SafeFileUtils.rmdirSync(dirPath);
    } catch (error) {
      logger.error(TAG, `删除目录失败: ${dirPath}, ${error}`);
    }
  }
}
