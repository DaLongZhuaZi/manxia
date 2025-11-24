// 文件路径: src/main/ets/Framework/Cache/OnlineImageLoader.ets
/**
 * 在线图片加载器
 * 专门处理在线漫画图片的加载，与本地图片加载分离
 * 特性：
 * 1. 请求队列管理（按优先级排序）
 * 2. 并发控制（最多2个并发请求，避免触发服务器限流）
 * 3. 轻量级内存缓存（不写磁盘）
 * 4. 智能重试机制
 */

import { image } from '@kit.ImageKit';
import { logger } from '../../Utils/Logger';
import { http } from '@kit.NetworkKit';
import CookieManager from '../Managers/CookieManager';

const TAG = 'OnlineImageLoader';

export interface OnlineLoadOptions {
  width?: number;
  height?: number;
  headers?: RequestHeaders;
  sourceId?: number;
  priority?: number;  // 优先级：10=当前页，5=下一页，3=下下页，1=其他
}

export interface RequestHeaders {
  userAgent?: string;
  accept?: string;
  referer?: string;
  origin?: string;
  cookie?: string;
  authorization?: string;
  acceptLanguage?: string;
  cacheControl?: string;
  pragma?: string;
  secFetchDest?: string;
  secFetchMode?: string;
  secFetchSite?: string;
}

interface HttpHeadersObject {
  'User-Agent'?: string;
  'Origin'?: string;
  'Accept'?: string;
  'Referer'?: string;
  'Cookie'?: string;
  'Authorization'?: string;
  'Accept-Language'?: string;
  'Cache-Control'?: string;
  'Pragma'?: string;
  'Sec-Fetch-Dest'?: string;
  'Sec-Fetch-Mode'?: string;
  'Sec-Fetch-Site'?: string;
}

interface QueuedRequest {
  url: string;
  options: OnlineLoadOptions;
  priority: number;
  resolve: (value: image.PixelMap | null) => void;
  reject: (reason: Error) => void;
  retryCount: number;
}

interface CacheEntry {
  pixelMap: image.PixelMap;
  size: number;
  timestamp: number;
}

interface CookieCacheEntry {
  cookie: string;
  timestamp: number;
}

export interface CacheStatsInfo {
  count: number;
  size: number;
  queueSize: number;
  activeRequests: number;
}

export class OnlineImageLoader {
  private static instance: OnlineImageLoader | null = null;
  
  // 请求队列
  private requestQueue: QueuedRequest[] = [];
  private activeRequests: number = 0;
  private readonly MAX_CONCURRENT = 4;  // 最多4个并发请求（优化条漫体验）
  
  // 轻量级内存缓存
  private memoryCache = new Map<string, CacheEntry>();
  private memoryCacheSize = 0;
  private readonly MAX_CACHE_SIZE = 50 * 1024 * 1024;  // 50MB
  private readonly MAX_CACHE_COUNT = 50;  // 最多缓存50张
  
  // Cookie缓存
  private cookieCache = new Map<number, CookieCacheEntry>();
  private readonly COOKIE_CACHE_TTL = 5 * 60 * 1000;  // 5分钟
  
  // 配置
  private readonly TIMEOUT = 30000;  // 30秒超时（适应26秒限流）
  private readonly MAX_RETRIES = 2;
  private readonly RETRY_DELAY = 1000;
  private readonly MIN_REQUEST_INTERVAL = 50;  // 50ms最小请求间隔（优化条漫体验）
  private lastRequestTime = 0;

  private constructor() {
    logger.info(TAG, '在线图片加载器初始化');
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): OnlineImageLoader {
    if (!OnlineImageLoader.instance) {
      OnlineImageLoader.instance = new OnlineImageLoader();
    }
    return OnlineImageLoader.instance;
  }

  /**
   * 加载在线图片
   */
  public async load(url: string, options?: OnlineLoadOptions): Promise<image.PixelMap | null> {
    const cacheKey = this.generateCacheKey(url);
    const priority = options?.priority || 1;
    
    // 1. 检查内存缓存
    const cached = this.getFromCache(cacheKey);
    if (cached) {
      logger.debug(TAG, `命中内存缓存: ${url.substring(0, 80)}`);
      return cached;
    }
    
    // 2. 加入请求队列
    return new Promise<image.PixelMap | null>((resolve, reject) => {
      const request: QueuedRequest = {
        url,
        options: options || {},
        priority,
        resolve,
        reject,
        retryCount: 0
      };
      
      this.requestQueue.push(request);
      this.sortQueue();
      
      logger.debug(TAG, `加入队列: url=${url.substring(0, 80)}, priority=${priority}, queueSize=${this.requestQueue.length}`);
      
      // 触发队列处理
      this.processQueue();
    });
  }

  /**
   * 处理请求队列
   */
  private async processQueue(): Promise<void> {
    // 检查是否可以处理新请求
    if (this.activeRequests >= this.MAX_CONCURRENT || this.requestQueue.length === 0) {
      return;
    }
    
    // 取出优先级最高的请求
    const request = this.requestQueue.shift();
    if (!request) {
      return;
    }
    
    this.activeRequests++;
    
    try {
      // 请求间隔控制
      await this.waitForInterval();
      
      // 执行HTTP请求
      const pixelMap = await this.httpRequest(request.url, request.options);
      
      if (pixelMap) {
        // 存入缓存
        this.putToCache(this.generateCacheKey(request.url), pixelMap);
        request.resolve(pixelMap);
      } else {
        request.resolve(null);
      }
      
    } catch (error) {
      // 重试逻辑
      if (request.retryCount < this.MAX_RETRIES) {
        request.retryCount++;
        logger.warn(TAG, `请求失败，准备重试 (${request.retryCount}/${this.MAX_RETRIES}): ${request.url.substring(0, 80)}`);
        
        // 重新加入队列（降低优先级）
        request.priority = Math.max(1, request.priority - 1);
        this.requestQueue.push(request);
        this.sortQueue();
        
        // 延迟后重试
        setTimeout(() => this.processQueue(), this.RETRY_DELAY);
      } else {
        logger.error(TAG, `请求最终失败: ${request.url.substring(0, 80)}, error=${String(error)}`);
        request.reject(error as Error);
      }
    } finally {
      this.activeRequests--;
      
      // 继续处理队列
      this.processQueue();
    }
  }

  /**
   * HTTP请求
   */
  private async httpRequest(url: string, options: OnlineLoadOptions): Promise<image.PixelMap | null> {
    try {
      const httpRequest = http.createHttp();
      const startTs = Date.now();
      
      // 构建请求头
      const headers = await this.buildHeaders(url, options);
      
      logger.debug(TAG, `发起HTTP请求: url=${url.substring(0, 80)}, timeout=${this.TIMEOUT}`);
      
      const requestOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: this.TIMEOUT,
        readTimeout: this.TIMEOUT,
        header: headers as Object,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      };
      
      // 发送请求
      const response = await httpRequest.request(url, requestOptions);
      
      if (response.responseCode === 200 && response.result) {
        const duration = Date.now() - startTs;
        const imageBuffer = response.result as ArrayBuffer;
        const bytesLen = imageBuffer.byteLength;
        
        logger.info(TAG, `HTTP响应成功: code=200, bytes=${bytesLen}, duration=${duration}ms`);
        
        // 创建PixelMap
        const imageSource = image.createImageSource(imageBuffer);
        const decodingOptions: image.DecodingOptions = {
          desiredSize: options.width && options.height ? 
            { width: options.width, height: options.height } : undefined,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888
        };
        
        const pixelMap = await imageSource.createPixelMap(decodingOptions);
        
        httpRequest.destroy();
        return pixelMap;
        
      } else {
        const duration = Date.now() - startTs;
        logger.warn(TAG, `HTTP响应失败: code=${response.responseCode}, duration=${duration}ms`);
        throw new Error(`HTTP请求失败: ${response.responseCode}`);
      }
      
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `HTTP请求异常: ${errMsg}`);
      throw new Error(errMsg);
    }
  }

  /**
   * 构建请求头
   */
  private async buildHeaders(url: string, options: OnlineLoadOptions): Promise<HttpHeadersObject> {
    const defaultUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
    const defaultAccept = 'image/avif,image/webp,image/png,image/jpeg;q=0.9,*/*;q=0.5';
    const defaultLang = 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7';
    
    const ua = options.headers?.userAgent || defaultUa;
    const accept = options.headers?.accept || defaultAccept;
    const referer = options.headers?.referer || '';
    const origin = options.headers?.origin || '';
    
    // 获取Cookie
    let cookie = options.headers?.cookie || '';
    if (!cookie && options.sourceId) {
      cookie = await this.getCachedCookie(options.sourceId);
    }
    
    const authorization = options.headers?.authorization || '';
    const acceptLanguage = options.headers?.acceptLanguage || defaultLang;
    const cacheControl = options.headers?.cacheControl || '';
    const pragma = options.headers?.pragma || '';
    const secFetchDest = options.headers?.secFetchDest || 'image';
    const secFetchMode = options.headers?.secFetchMode || 'no-cors';
    
    // 自动判断Sec-Fetch-Site
    let secFetchSite = 'same-origin';
    if (options.headers?.secFetchSite) {
      secFetchSite = options.headers.secFetchSite;
    } else if (referer) {
      const urlHost = this.extractHost(url);
      const refererHost = this.extractHost(referer);
      secFetchSite = (urlHost === refererHost) ? 'same-origin' : 'cross-site';
    }
    
    const headerObj: HttpHeadersObject = {
      'User-Agent': ua,
      'Origin': origin || (referer || undefined),
      'Accept': accept,
      'Referer': referer || undefined,
      'Cookie': cookie || undefined,
      'Authorization': authorization || undefined,
      'Accept-Language': acceptLanguage || undefined,
      'Cache-Control': cacheControl || undefined,
      'Pragma': pragma || undefined,
      'Sec-Fetch-Dest': secFetchDest || undefined,
      'Sec-Fetch-Mode': secFetchMode || undefined,
      'Sec-Fetch-Site': secFetchSite || undefined
    };
    
    return headerObj;
  }

  /**
   * 获取缓存的Cookie
   */
  private async getCachedCookie(sourceId: number): Promise<string> {
    const now = Date.now();
    const cached = this.cookieCache.get(sourceId);
    
    if (cached && (now - cached.timestamp) < this.COOKIE_CACHE_TTL) {
      return cached.cookie;
    }
    
    // 从数据库获取
    try {
      const cookieManager = CookieManager.getInstance();
      const cookie = await cookieManager.getCookieString(sourceId);
      if (cookie) {
        const entry: CookieCacheEntry = { cookie: cookie, timestamp: now };
        this.cookieCache.set(sourceId, entry);
        return cookie;
      }
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `获取Cookie失败: sourceId=${sourceId}, error=${errMsg}`);
    }
    
    return '';
  }

  /**
   * 提取主机名
   */
  private extractHost(url: string): string {
    try {
      const match = url.match(/^https?:\/\/([^\/]+)/);
      if (match && match.length > 1) {
        return match[1];
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  /**
   * 等待请求间隔
   */
  private async waitForInterval(): Promise<void> {
    const now = Date.now();
    const elapsed = now - this.lastRequestTime;
    
    if (elapsed < this.MIN_REQUEST_INTERVAL) {
      const waitTime = this.MIN_REQUEST_INTERVAL - elapsed;
      await new Promise<void>(resolve => setTimeout(resolve, waitTime));
    }
    
    this.lastRequestTime = Date.now();
  }

  /**
   * 队列排序（按优先级降序）
   */
  private sortQueue(): void {
    this.requestQueue.sort((a, b) => b.priority - a.priority);
  }

  /**
   * 生成缓存键
   */
  private generateCacheKey(url: string): string {
    // 使用URL的hash作为缓存键
    let hash = 0;
    for (let i = 0; i < url.length; i++) {
      const char = url.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash;
    }
    return `online_${Math.abs(hash).toString(36)}`;
  }

  /**
   * 从缓存获取
   */
  private getFromCache(cacheKey: string): image.PixelMap | null {
    const entry = this.memoryCache.get(cacheKey);
    if (entry) {
      // 更新时间戳
      entry.timestamp = Date.now();
      return entry.pixelMap;
    }
    return null;
  }

  /**
   * 存入缓存
   */
  private async putToCache(cacheKey: string, pixelMap: image.PixelMap): Promise<void> {
    try {
      const size = await this.calculatePixelMapSize(pixelMap);
      
      // 检查是否需要清理
      this.evictCacheIfNeeded(size);
      
      const entry: CacheEntry = {
        pixelMap,
        size,
        timestamp: Date.now()
      };
      
      this.memoryCache.set(cacheKey, entry);
      this.memoryCacheSize += size;
      
      logger.debug(TAG, `存入缓存: key=${cacheKey}, size=${size}, total=${this.memoryCacheSize}`);
      
    } catch (error) {
      logger.error(TAG, `存入缓存失败: ${String(error)}`);
    }
  }

  /**
   * 计算PixelMap大小
   */
  private async calculatePixelMapSize(pixelMap: image.PixelMap): Promise<number> {
    try {
      const imageInfo = await pixelMap.getImageInfo();
      return imageInfo.size.width * imageInfo.size.height * 4;  // RGBA
    } catch (e) {
      return 1024 * 1024;  // 默认1MB
    }
  }

  /**
   * 缓存淘汰
   */
  private evictCacheIfNeeded(newSize: number): void {
    // 检查大小和数量限制
    while (
      (this.memoryCacheSize + newSize > this.MAX_CACHE_SIZE) ||
      (this.memoryCache.size >= this.MAX_CACHE_COUNT)
    ) {
      if (this.memoryCache.size === 0) break;
      
      // LRU淘汰：找到最旧的条目
      let oldestKey: string | null = null;
      let oldestTime = Date.now();
      
      const entries = this.memoryCache.entries();
      let result = entries.next();
      while (!result.done) {
        const key = result.value[0];
        const entry = result.value[1];
        if (entry.timestamp < oldestTime) {
          oldestTime = entry.timestamp;
          oldestKey = key;
        }
        result = entries.next();
      }
      
      if (oldestKey) {
        const entry = this.memoryCache.get(oldestKey);
        if (entry) {
          this.memoryCacheSize -= entry.size;
          this.memoryCache.delete(oldestKey);
          logger.debug(TAG, `淘汰缓存: key=${oldestKey}, size=${entry.size}`);
        }
      } else {
        break;
      }
    }
  }

  /**
   * 清空缓存
   */
  public clearCache(): void {
    this.memoryCache.clear();
    this.memoryCacheSize = 0;
    logger.info(TAG, '缓存已清空');
  }

  /**
   * 获取缓存统计
   */
  public getCacheStats(): CacheStatsInfo {
    const stats: CacheStatsInfo = {
      count: this.memoryCache.size,
      size: this.memoryCacheSize,
      queueSize: this.requestQueue.length,
      activeRequests: this.activeRequests
    };
    return stats;
  }

  /**
   * 取消所有待处理请求
   */
  public cancelAll(): void {
    const count = this.requestQueue.length;
    this.requestQueue.forEach(req => {
      req.reject(new Error('Request cancelled'));
    });
    this.requestQueue = [];
    logger.info(TAG, `已取消 ${count} 个待处理请求`);
  }
}
