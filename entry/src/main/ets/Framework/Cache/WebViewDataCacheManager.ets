// 文件路径: entry/src/main/ets/Framework/Cache/WebViewDataCacheManager.ets
/**
 * WebView数据缓存管理器
 * 用于缓存漫画详情、章节列表等数据，减少网络请求
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { MangaInfo, ChapterInfo } from 'manxia_source_engine/src/main/ets/Framework/WebView/MangaSourceTypes';

const TAG = 'WebViewDataCacheManager';

/**
 * 缓存项接口
 */
interface CacheItem<T> {
  data: T;
  timestamp: number;
  expireTime: number;
}

/**
 * 缓存配置
 */
export interface CacheConfig {
  /** 漫画详情缓存时间（毫秒），默认30分钟 */
  mangaDetailTTL: number;
  /** 章节列表缓存时间（毫秒），默认15分钟 */
  chapterListTTL: number;
  /** 最大缓存条目数 */
  maxEntries: number;
}

/**
 * 缓存统计信息
 */
export interface CacheStats {
  mangaDetailCount: number;
  chapterListCount: number;
  totalCount: number;
}

/**
 * WebView数据缓存管理器
 */
export class WebViewDataCacheManager {
  private static instance: WebViewDataCacheManager | null = null;
  
  // 漫画详情缓存 key: sourceId_mangaId
  private mangaDetailCache = new Map<string, CacheItem<MangaInfo>>();
  
  // 章节列表缓存 key: sourceId_mangaId
  private chapterListCache = new Map<string, CacheItem<ChapterInfo[]>>();
  
  // 缓存配置
  private config: CacheConfig = {
    mangaDetailTTL: 30 * 60 * 1000,  // 30分钟
    chapterListTTL: 15 * 60 * 1000,  // 15分钟
    maxEntries: 100
  };
  
  private constructor() {
    logger.info(TAG, '初始化WebView数据缓存管理器');
  }
  
  /**
   * 获取单例实例
   */
  static getInstance(): WebViewDataCacheManager {
    if (!WebViewDataCacheManager.instance) {
      WebViewDataCacheManager.instance = new WebViewDataCacheManager();
    }
    return WebViewDataCacheManager.instance;
  }
  
  /**
   * 更新缓存配置
   */
  updateConfig(config: CacheConfig): void {
    // 手动更新配置属性
    const newConfig: CacheConfig = {
      mangaDetailTTL: config.mangaDetailTTL,
      chapterListTTL: config.chapterListTTL,
      maxEntries: config.maxEntries
    };
    this.config = newConfig;
    logger.info(TAG, `缓存配置已更新: ${JSON.stringify(this.config)}`);
  }
  
  /**
   * 生成缓存键
   */
  private generateKey(sourceId: number, mangaId: string): string {
    return `${sourceId}_${mangaId}`;
  }
  
  /**
   * 检查缓存项是否过期
   */
  private isExpired<T>(item: CacheItem<T>): boolean {
    return Date.now() > item.expireTime;
  }
  
  /**
   * 清理过期缓存
   */
  private cleanExpiredCache<T>(cache: Map<string, CacheItem<T>>): void {
    const expiredKeys: string[] = [];
    
    cache.forEach((item, key) => {
      if (this.isExpired(item)) {
        expiredKeys.push(key);
      }
    });
    
    expiredKeys.forEach(key => {
      cache.delete(key);
      logger.debug(TAG, `删除过期缓存: ${key}`);
    });
    
    if (expiredKeys.length > 0) {
      logger.info(TAG, `清理了 ${expiredKeys.length} 个过期缓存项`);
    }
  }
  
  /**
   * 限制缓存大小（LRU策略）
   */
  private limitCacheSize<T>(cache: Map<string, CacheItem<T>>): void {
    if (cache.size <= this.config.maxEntries) {
      return;
    }
    
    // 按访问时间排序，删除最旧的
    const entries = Array.from(cache.entries());
    entries.sort((a, b) => a[1].timestamp - b[1].timestamp);
    
    const deleteCount = cache.size - this.config.maxEntries;
    for (let i = 0; i < deleteCount; i++) {
      const key = entries[i][0];
      cache.delete(key);
      logger.debug(TAG, `删除最旧缓存: ${key}`);
    }
    
    logger.info(TAG, `限制缓存大小，删除了 ${deleteCount} 个最旧缓存项`);
  }
  
  // ==================== 漫画详情缓存 ====================
  
  /**
   * 获取漫画详情缓存
   */
  getMangaDetail(sourceId: number, mangaId: string): MangaInfo | null {
    const key = this.generateKey(sourceId, mangaId);
    const item = this.mangaDetailCache.get(key);
    
    if (!item) {
      logger.debug(TAG, `漫画详情缓存未命中: ${key}`);
      return null;
    }
    
    if (this.isExpired(item)) {
      this.mangaDetailCache.delete(key);
      logger.debug(TAG, `漫画详情缓存已过期: ${key}`);
      return null;
    }
    
    // 更新访问时间
    item.timestamp = Date.now();
    logger.debug(TAG, `漫画详情缓存命中: ${key}`);
    return item.data;
  }
  
  /**
   * 设置漫画详情缓存
   */
  setMangaDetail(sourceId: number, mangaId: string, data: MangaInfo): void {
    const key = this.generateKey(sourceId, mangaId);
    const now = Date.now();
    
    this.mangaDetailCache.set(key, {
      data,
      timestamp: now,
      expireTime: now + this.config.mangaDetailTTL
    });
    
    logger.info(TAG, `缓存漫画详情: ${key}, 标题: ${data.title}`);
    
    // 清理过期缓存并限制大小
    this.cleanExpiredCache(this.mangaDetailCache);
    this.limitCacheSize(this.mangaDetailCache);
  }
  
  /**
   * 删除漫画详情缓存
   */
  deleteMangaDetail(sourceId: number, mangaId: string): void {
    const key = this.generateKey(sourceId, mangaId);
    this.mangaDetailCache.delete(key);
    logger.info(TAG, `删除漫画详情缓存: ${key}`);
  }
  
  // ==================== 章节列表缓存 ====================
  
  /**
   * 获取章节列表缓存
   */
  getChapterList(sourceId: number, mangaId: string): ChapterInfo[] | null {
    const key = this.generateKey(sourceId, mangaId);
    const item = this.chapterListCache.get(key);
    
    if (!item) {
      logger.debug(TAG, `章节列表缓存未命中: ${key}`);
      return null;
    }
    
    if (this.isExpired(item)) {
      this.chapterListCache.delete(key);
      logger.debug(TAG, `章节列表缓存已过期: ${key}`);
      return null;
    }
    
    // 更新访问时间
    item.timestamp = Date.now();
    logger.debug(TAG, `章节列表缓存命中: ${key}, 章节数: ${item.data.length}`);
    return item.data;
  }
  
  /**
   * 设置章节列表缓存
   */
  setChapterList(sourceId: number, mangaId: string, data: ChapterInfo[]): void {
    const key = this.generateKey(sourceId, mangaId);
    const now = Date.now();
    
    this.chapterListCache.set(key, {
      data,
      timestamp: now,
      expireTime: now + this.config.chapterListTTL
    });
    
    logger.info(TAG, `缓存章节列表: ${key}, 章节数: ${data.length}`);
    
    // 清理过期缓存并限制大小
    this.cleanExpiredCache(this.chapterListCache);
    this.limitCacheSize(this.chapterListCache);
  }
  
  /**
   * 删除章节列表缓存
   */
  deleteChapterList(sourceId: number, mangaId: string): void {
    const key = this.generateKey(sourceId, mangaId);
    this.chapterListCache.delete(key);
    logger.info(TAG, `删除章节列表缓存: ${key}`);
  }
  
  // ==================== 缓存管理 ====================
  
  /**
   * 清空所有缓存
   */
  clearAll(): void {
    const totalCount = this.mangaDetailCache.size + this.chapterListCache.size;
    this.mangaDetailCache.clear();
    this.chapterListCache.clear();
    logger.info(TAG, `清空所有缓存，共 ${totalCount} 项`);
  }
  
  /**
   * 清空指定漫画的所有缓存
   */
  clearManga(sourceId: number, mangaId: string): void {
    this.deleteMangaDetail(sourceId, mangaId);
    this.deleteChapterList(sourceId, mangaId);
    logger.info(TAG, `清空漫画缓存: sourceId=${sourceId}, mangaId=${mangaId}`);
  }

  /**
   * 清空指定图源的详情和章节缓存
   */
  clearSource(sourceId: number): void {
    const prefix = `${sourceId}_`;
    let clearedCount = 0;
    const detailKeys = Array.from(this.mangaDetailCache.keys());
    for (let index = 0; index < detailKeys.length; index++) {
      const key = detailKeys[index];
      if (key.startsWith(prefix)) {
        this.mangaDetailCache.delete(key);
        clearedCount++;
      }
    }
    const chapterKeys = Array.from(this.chapterListCache.keys());
    for (let index = 0; index < chapterKeys.length; index++) {
      const key = chapterKeys[index];
      if (key.startsWith(prefix)) {
        this.chapterListCache.delete(key);
        clearedCount++;
      }
    }
    logger.info(TAG, `清空图源WebView数据缓存: sourceId=${sourceId}, count=${clearedCount}`);
  }
  
  /**
   * 清理所有过期缓存
   */
  cleanExpired(): void {
    this.cleanExpiredCache(this.mangaDetailCache);
    this.cleanExpiredCache(this.chapterListCache);
  }
  
  /**
   * 获取缓存统计信息
   */
  getStats(): CacheStats {
    const stats: CacheStats = {
      mangaDetailCount: this.mangaDetailCache.size,
      chapterListCount: this.chapterListCache.size,
      totalCount: this.mangaDetailCache.size + this.chapterListCache.size
    };
    return stats;
  }
  
  /**
   * 预热缓存（可选）
   */
  async warmup(sourceId: number, mangaIds: string[]): Promise<void> {
    logger.info(TAG, `开始预热缓存: sourceId=${sourceId}, 漫画数=${mangaIds.length}`);
    // 预热逻辑可以在需要时实现
  }
}
