/**
 * 封面图片管理器
 * 统一管理封面图片的加载和缓存，支持AVIF格式
 * 通过预加载网络图片到PixelMap，解决Image组件不支持AVIF的问题
 */

import { image } from '@kit.ImageKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { OnlineImageLoader, OnlineLoadOptions, RequestHeaders } from '../Cache/OnlineImageLoader';
import { isAvifFormat } from './AvifDecoder';

const TAG = 'CoverImageManager';
const MAX_COVER_CACHE_COUNT: number = 160;

// 封面缓存（URL -> PixelMap）
const coverCache: Map<string, image.PixelMap> = new Map();

// 正在加载的URL集合（防止重复加载）
const loadingUrls: Set<string> = new Set();

// 加载回调队列
const loadCallbacks: Map<string, Array<(pixelMap: image.PixelMap | null) => void>> = new Map();

function releaseCoverPixelMap(pixelMap: image.PixelMap): void {
  try {
    pixelMap.release();
  } catch (_e) {
    // 忽略释放错误
  }
}

function touchCoverCache(url: string, pixelMap: image.PixelMap): void {
  coverCache.delete(url);
  coverCache.set(url, pixelMap);
}

function evictCoverCacheIfNeeded(): void {
  while (coverCache.size > MAX_COVER_CACHE_COUNT) {
    let oldestUrl: string = '';
    for (const cacheKey of coverCache.keys()) {
      oldestUrl = cacheKey;
      break;
    }
    if (oldestUrl.length === 0) {
      break;
    }
    const pixelMap = coverCache.get(oldestUrl);
    coverCache.delete(oldestUrl);
    if (pixelMap) {
      releaseCoverPixelMap(pixelMap);
    }
    logger.debug(TAG, `淘汰封面内存缓存: ${oldestUrl.substring(0, 50)}...`);
  }
}

/**
 * 封面图片管理器单例
 */
export class CoverImageManager {
  private static instance: CoverImageManager | null = null;
  
  private constructor() {}
  
  static getInstance(): CoverImageManager {
    if (!CoverImageManager.instance) {
      CoverImageManager.instance = new CoverImageManager();
    }
    return CoverImageManager.instance;
  }
  
  /**
   * 获取封面PixelMap（如果已缓存）
   */
  getCachedPixelMap(url: string): image.PixelMap | null {
    const cached = coverCache.get(url);
    if (!cached) {
      return null;
    }
    touchCoverCache(url, cached);
    return cached;
  }
  
  /**
   * 检查URL是否可能是AVIF格式（通过URL后缀判断）
   */
  isPossibleAvifUrl(url: string): boolean {
    if (!url) return false;
    const lowerUrl = url.toLowerCase();
    return lowerUrl.includes('.avif') || lowerUrl.includes('format=avif');
  }
  
  /**
   * 预加载封面图片
   * 对于可能是AVIF格式的网络图片，使用OnlineImageLoader加载
   */
  async preloadCover(url: string, options?: OnlineLoadOptions): Promise<image.PixelMap | null> {
    if (!url || !url.startsWith('http')) {
      return null;
    }
    
    // 检查缓存
    const cached = coverCache.get(url);
    if (cached) {
      touchCoverCache(url, cached);
      return cached;
    }
    
    // 检查是否正在加载
    if (loadingUrls.has(url)) {
      // 等待加载完成
      return new Promise((resolve) => {
        const callbacks = loadCallbacks.get(url) || [];
        callbacks.push(resolve);
        loadCallbacks.set(url, callbacks);
      });
    }
    
    // 标记为正在加载
    loadingUrls.add(url);
    
    try {
      const loader = OnlineImageLoader.getInstance();
      const requestHeaders: RequestHeaders = {} as RequestHeaders;
      if (options && options.headers) {
        if (options.headers.userAgent) {
          requestHeaders.userAgent = options.headers.userAgent;
        }
        if (options.headers.accept) {
          requestHeaders.accept = options.headers.accept;
        }
        if (options.headers.referer) {
          requestHeaders.referer = options.headers.referer;
        }
        if (options.headers.origin) {
          requestHeaders.origin = options.headers.origin;
        }
        if (options.headers.cookie) {
          requestHeaders.cookie = options.headers.cookie;
        }
        if (options.headers.authorization) {
          requestHeaders.authorization = options.headers.authorization;
        }
        if (options.headers.acceptLanguage) {
          requestHeaders.acceptLanguage = options.headers.acceptLanguage;
        }
        if (options.headers.cacheControl) {
          requestHeaders.cacheControl = options.headers.cacheControl;
        }
        if (options.headers.pragma) {
          requestHeaders.pragma = options.headers.pragma;
        }
        if (options.headers.secFetchDest) {
          requestHeaders.secFetchDest = options.headers.secFetchDest;
        }
        if (options.headers.secFetchMode) {
          requestHeaders.secFetchMode = options.headers.secFetchMode;
        }
        if (options.headers.secFetchSite) {
          requestHeaders.secFetchSite = options.headers.secFetchSite;
        }
        if (options.headers.cachePartition) {
          requestHeaders.cachePartition = options.headers.cachePartition;
        }
      }
      if (!requestHeaders.referer) {
        requestHeaders.referer = url.split('/').slice(0, 3).join('/') + '/';
      }
      const requestOptions: OnlineLoadOptions = {
        width: options?.width,
        height: options?.height,
        headers: requestHeaders,
        sourceId: options?.sourceId,
        priority: options?.priority || 5,
        partitionKey: options?.partitionKey
      };
      const pixelMap = await loader.load(url, requestOptions);
      
      if (pixelMap) {
        // 缓存结果
        const oldPixelMap = coverCache.get(url);
        if (oldPixelMap && oldPixelMap !== pixelMap) {
          releaseCoverPixelMap(oldPixelMap);
        }
        touchCoverCache(url, pixelMap);
        evictCoverCacheIfNeeded();
        logger.debug(TAG, `封面预加载成功: ${url.substring(0, 50)}...`);
      }
      
      // 通知等待的回调
      const callbacks = loadCallbacks.get(url) || [];
      const callbacksSnapshot: Array<(pixelMap: image.PixelMap | null) => void> = callbacks.slice();
      callbacksSnapshot.forEach(cb => cb(pixelMap));
      loadCallbacks.delete(url);
      
      return pixelMap;
    } catch (e) {
      logger.warn(TAG, `封面预加载失败: ${url.substring(0, 50)}..., ${e}`);
      
      // 通知等待的回调
      const callbacks = loadCallbacks.get(url) || [];
      const callbacksSnapshot: Array<(pixelMap: image.PixelMap | null) => void> = callbacks.slice();
      callbacksSnapshot.forEach(cb => cb(null));
      loadCallbacks.delete(url);
      
      return null;
    } finally {
      loadingUrls.delete(url);
    }
  }
  
  /**
   * 批量预加载封面
   */
  async preloadCovers(urls: string[]): Promise<void> {
    const networkUrls = urls.filter(url => url && url.startsWith('http'));
    
    // 并发加载，但限制并发数
    const concurrency = 3;
    for (let i = 0; i < networkUrls.length; i += concurrency) {
      const batch = networkUrls.slice(i, i + concurrency);
      await Promise.all(batch.map(url => this.preloadCover(url)));
    }
  }
  
  /**
   * 清理缓存
   */
  clearCache(): void {
    coverCache.forEach((pixelMap) => {
      releaseCoverPixelMap(pixelMap);
    });
    coverCache.clear();
    logger.info(TAG, '封面缓存已清理');
  }
  
  /**
   * 获取缓存大小
   */
  getCacheSize(): number {
    return coverCache.size;
  }
  
  /**
   * 从缓存中移除指定URL
   */
  removeFromCache(url: string): void {
    const pixelMap = coverCache.get(url);
    if (pixelMap) {
      releaseCoverPixelMap(pixelMap);
      coverCache.delete(url);
    }
  }
}

/**
 * 获取封面图片管理器实例
 */
export function getCoverImageManager(): CoverImageManager {
  return CoverImageManager.getInstance();
}
