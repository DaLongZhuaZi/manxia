import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * 图源内容缓存管理器
 * 缓存图源详情页的所有工作流数据（热门、最新、搜索、筛选等）
 * 支持缓存优先显示 + 后台自动更新
 */

import { logger } from '../../Utils/Logger';
import { ComicInfo } from '../Source/SourceExecutor';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { uiContextManager } from '../Managers/UIContextManager';

const TAG = 'SourceContentCache';

/**
 * 缓存数据项
 */
export interface CachedContent {
  sourceId: number;
  workflowType: string;  // 'popular', 'latest', 'search', 'filter', etc.
  workflowKey: string;   // 唯一标识，如 'popular', 'search:keyword', 'filter:params'
  comics: ComicInfo[];
  page: number;
  hasMore: boolean;
  timestamp: number;     // 缓存时间戳
  expiresAt: number;     // 过期时间戳
}

/**
 * 缓存配置
 */
interface CacheConfig {
  maxAge: number;        // 最大缓存时间（毫秒）
  maxEntries: number;    // 每个图源最多缓存条目数
}

/**
 * 缓存统计信息
 */
export interface CacheStats {
  totalEntries: number;
  totalComics: number;
  sources: number;
}

/**
 * 图源内容缓存管理器
 */
export class SourceContentCache {
  private static instance: SourceContentCache | null = null;
  private cacheMap: Map<string, CachedContent> = new Map();
  private config: CacheConfig = {
    maxAge: 30 * 60 * 1000,  // 30分钟
    maxEntries: 20            // 每个图源最多20个缓存条目
  };

  private getAbilityContext(): common.UIAbilityContext {
    const context = uiContextManager.getAbilityContext();
    if (!context) {
      throw new Error('SourceContentCache 获取 AbilityContext 失败');
    }
    return context;
  }

  private constructor() {
    this.loadCacheFromStorage();
  }

  static getInstance(): SourceContentCache {
    if (!SourceContentCache.instance) {
      SourceContentCache.instance = new SourceContentCache();
    }
    return SourceContentCache.instance;
  }

  /**
   * 生成缓存键
   */
  private generateCacheKey(sourceId: number, workflowKey: string): string {
    return `${sourceId}:${workflowKey}`;
  }

  /**
   * 设置缓存
   */
  set(sourceId: number, workflowType: string, workflowKey: string, comics: ComicInfo[], page: number, hasMore: boolean): void {
    const cacheKey = this.generateCacheKey(sourceId, workflowKey);
    const now = Date.now();
    
    const cachedContent: CachedContent = {
      sourceId,
      workflowType,
      workflowKey,
      comics,
      page,
      hasMore,
      timestamp: now,
      expiresAt: now + this.config.maxAge
    };

    this.cacheMap.set(cacheKey, cachedContent);
    logger.info(TAG, `缓存已保存: ${cacheKey}, 漫画数量: ${comics.length}, 页码: ${page}`);

    // 清理过期缓存
    this.cleanExpiredCache();
    
    // 限制缓存条目数
    this.limitCacheEntries(sourceId);
    
    // 持久化到存储
    this.saveCacheToStorage();
  }

  /**
   * 获取缓存
   */
  get(sourceId: number, workflowKey: string): CachedContent | null {
    const cacheKey = this.generateCacheKey(sourceId, workflowKey);
    const cached = this.cacheMap.get(cacheKey);

    if (!cached) {
      return null;
    }

    // 检查是否过期
    if (Date.now() > cached.expiresAt) {
      logger.info(TAG, `缓存已过期: ${cacheKey}`);
      this.cacheMap.delete(cacheKey);
      return null;
    }

    logger.info(TAG, `缓存命中: ${cacheKey}, 漫画数量: ${cached.comics.length}`);
    return cached;
  }

  /**
   * 追加缓存（用于分页加载）
   */
  append(sourceId: number, workflowKey: string, newComics: ComicInfo[], newPage: number, hasMore: boolean): void {
    const cacheKey = this.generateCacheKey(sourceId, workflowKey);
    const existing = this.cacheMap.get(cacheKey);

    if (!existing) {
      logger.warn(TAG, `追加缓存失败，未找到基础缓存: ${cacheKey}`);
      return;
    }

    // 合并漫画列表（去重）
    const existingIds = new Set(existing.comics.map(c => c.id));
    const uniqueNewComics = newComics.filter(c => !existingIds.has(c.id));
    
    existing.comics.push(...uniqueNewComics);
    existing.page = newPage;
    existing.hasMore = hasMore;
    existing.timestamp = Date.now();
    existing.expiresAt = Date.now() + this.config.maxAge;

    logger.info(TAG, `缓存已追加: ${cacheKey}, 新增: ${uniqueNewComics.length}, 总数: ${existing.comics.length}`);
    
    this.saveCacheToStorage();
  }

  /**
   * 检查缓存是否存在且未过期
   */
  has(sourceId: number, workflowKey: string): boolean {
    const cached = this.get(sourceId, workflowKey);
    return cached !== null;
  }

  /**
   * 检查缓存是否需要刷新（接近过期）
   */
  needsRefresh(sourceId: number, workflowKey: string): boolean {
    const cacheKey = this.generateCacheKey(sourceId, workflowKey);
    const cached = this.cacheMap.get(cacheKey);

    if (!cached) {
      return true;
    }

    // 如果缓存时间超过一半，建议刷新
    const age = Date.now() - cached.timestamp;
    return age > this.config.maxAge / 2;
  }

  /**
   * 清除指定图源的所有缓存
   */
  clearSource(sourceId: number): void {
    const keysToDelete: string[] = [];
    
    this.cacheMap.forEach((value, key) => {
      if (value.sourceId === sourceId) {
        keysToDelete.push(key);
      }
    });

    keysToDelete.forEach(key => this.cacheMap.delete(key));
    logger.info(TAG, `已清除图源 ${sourceId} 的所有缓存，共 ${keysToDelete.length} 项`);
    
    this.saveCacheToStorage();
  }

  /**
   * 清除指定工作流的缓存
   */
  clearWorkflow(sourceId: number, workflowKey: string): void {
    const cacheKey = this.generateCacheKey(sourceId, workflowKey);
    if (this.cacheMap.delete(cacheKey)) {
      logger.info(TAG, `已清除缓存: ${cacheKey}`);
      this.saveCacheToStorage();
    }
  }

  /**
   * 清理过期缓存
   */
  private cleanExpiredCache(): void {
    const now = Date.now();
    const keysToDelete: string[] = [];

    this.cacheMap.forEach((value, key) => {
      if (now > value.expiresAt) {
        keysToDelete.push(key);
      }
    });

    keysToDelete.forEach(key => this.cacheMap.delete(key));
    
    if (keysToDelete.length > 0) {
      logger.info(TAG, `已清理 ${keysToDelete.length} 个过期缓存`);
    }
  }

  /**
   * 限制每个图源的缓存条目数
   */
  private limitCacheEntries(sourceId: number): void {
    const sourceEntries: Array<[string, CachedContent]> = [];
    
    this.cacheMap.forEach((value, key) => {
      if (value.sourceId === sourceId) {
        sourceEntries.push([key, value]);
      }
    });

    if (sourceEntries.length > this.config.maxEntries) {
      // 按时间戳排序，删除最旧的
      sourceEntries.sort((a, b) => a[1].timestamp - b[1].timestamp);
      
      const toDelete = sourceEntries.slice(0, sourceEntries.length - this.config.maxEntries);
      toDelete.forEach((entry: [string, CachedContent]) => {
        this.cacheMap.delete(entry[0]);
      });
      
      logger.info(TAG, `图源 ${sourceId} 缓存条目超限，已删除 ${toDelete.length} 个最旧条目`);
    }
  }

  /**
   * 从存储加载缓存
   */
  private async loadCacheFromStorage(): Promise<void> {
    try {
      const dataPreferences = await preferences.getPreferences(this.getAbilityContext(), 'source_content_cache');
      const cacheJson = await dataPreferences.get('cache_data', '{}') as string;
      
      if (cacheJson && cacheJson !== '{}') {
        const cacheData = SafeUtils.parseObj(cacheJson) as Record<string, CachedContent>;
        
        // 恢复到Map
        Object.entries(cacheData).forEach((entry: [string, CachedContent]) => {
          this.cacheMap.set(entry[0], entry[1]);
        });
        
        logger.info(TAG, `从存储加载了 ${this.cacheMap.size} 个缓存条目`);
        
        // 清理过期缓存
        this.cleanExpiredCache();
      }
    } catch (error) {
      logger.error(TAG, '加载缓存失败', String(error));
    }
  }

  /**
   * 保存缓存到存储
   */
  private async saveCacheToStorage(): Promise<void> {
    try {
      const dataPreferences = await preferences.getPreferences(this.getAbilityContext(), 'source_content_cache');
      
      // 转换Map为普通对象
      const cacheData: Record<string, CachedContent> = {};
      this.cacheMap.forEach((value, key) => {
        cacheData[key] = value;
      });
      
      await dataPreferences.put('cache_data', JSON.stringify(cacheData));
      await dataPreferences.flush();
      
      logger.debug(TAG, `缓存已保存到存储，共 ${this.cacheMap.size} 个条目`);
    } catch (error) {
      logger.error(TAG, '保存缓存失败', String(error));
    }
  }

  /**
   * 清空所有缓存
   */
  async clearAll(): Promise<void> {
    this.cacheMap.clear();
    logger.info(TAG, '已清空所有缓存');
    
    try {
      const dataPreferences = await preferences.getPreferences(this.getAbilityContext(), 'source_content_cache');
      await dataPreferences.delete('cache_data');
      await dataPreferences.flush();
    } catch (error) {
      logger.error(TAG, '清空存储缓存失败', String(error));
    }
  }

  /**
   * 获取缓存统计信息
   */
  getStats(): CacheStats {
    const sourceSet = new Set<number>();
    let totalComics = 0;

    this.cacheMap.forEach(value => {
      sourceSet.add(value.sourceId);
      totalComics += value.comics.length;
    });

    const stats: CacheStats = {
      totalEntries: this.cacheMap.size,
      totalComics: totalComics,
      sources: sourceSet.size
    };
    return stats;
  }
}
