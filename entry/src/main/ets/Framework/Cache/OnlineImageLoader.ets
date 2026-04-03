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
import { webview } from '@kit.ArkWeb';
import CookieManager from '../Managers/CookieManager';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { DiskCacheManager } from './DiskCacheManager';
import { DataManager } from '../Data/DataManager';
import { JinmantiantangDescrambler, JinmantiantangParameters } from '../ImageProcessing/JinmantiantangDescrambler';
import { UserAgentManager } from '../Managers/UserAgentManager';
import { AvifDecoder, isAvifFormat } from '../Image/AvifDecoder';
import { GlobalWebViewContainer, WebViewEventCallbacks } from '../WebView/WebViewContainerPage';
import { WebViewSourceConfig } from '../WebView/WebViewImageLoader';


const TAG = 'OnlineImageLoader';

// 禁漫天堂解扰器实例（懒加载）
let jinmantiantangDescrambler: JinmantiantangDescrambler | null = null;

function getJinmantiantangDescrambler(): JinmantiantangDescrambler {
  if (jinmantiantangDescrambler === null) {
    jinmantiantangDescrambler = new JinmantiantangDescrambler();
  }
  return jinmantiantangDescrambler;
}

export interface OnlineLoadOptions {
  width?: number;
  height?: number;
  headers?: RequestHeaders;
  sourceId?: number;
  priority?: number;  // 优先级：10=当前页，5=下一页，3=下下页，1=其他
  partitionKey?: string;
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
  cachePartition?: string;
}


interface HttpHeadersObject {
  userAgent?: string;
  origin?: string;
  accept?: string;
  referer?: string;
  cookie?: string;
  authorization?: string;
  acceptLanguage?: string;
  cacheControl?: string;
  pragma?: string;
  secFetchDest?: string;
  secFetchMode?: string;
  secFetchSite?: string;
}

interface HttpRequestHeadersObject {
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

interface CacheStatusUpdateValue {
  localPath: string;
  fileSize: number;
}

interface CacheStatusUpdatePayload {
  imageUrl: string;
  localPath: string;
  fileSize: number;
}

interface RmcdnWebViewWaiter {
  resolve: () => void;
  reject: (reason: Error) => void;
}

export interface CacheStatsInfo {
  count: number;
  size: number;
  queueSize: number;
  activeRequests: number;
}

export class OnlineImageLoader {
  private static instance: OnlineImageLoader | null = null;
  private readonly photos18Pkg: string = 'com.manxia.extension.all.photos18';
  private readonly rmcdnFallbackPrefix: string = 'online_image_rmcdn_fallback';
  
  // 请求队列

  private requestQueue: QueuedRequest[] = [];
  private activeRequests: number = 0;
  private readonly MAX_CONCURRENT = 10;  // 【修复】提升到10个并发，加快封面加载速度
  
  // [修复] 正在加载的URL集合，用于去重
  private loadingUrls = new Set<string>();

  // 缓存状态写库队列（按URL去重，批量异步落库）
  private pendingCacheStatusUpdates = new Map<string, CacheStatusUpdateValue>();
  private cacheStatusFlushTimer: number | null = null;
  private isFlushingCacheStatusUpdates = false;
  private readonly CACHE_STATUS_FLUSH_DELAY = 150;
  
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
  private readonly RMCDN_WEBVIEW_ATTACH_RETRIES = 12;
  private readonly RMCDN_WEBVIEW_ATTACH_DELAY = 120;
  private readonly RMCDN_WEBVIEW_LOAD_TIMEOUT = 15000;
  private readonly RMCDN_WEBVIEW_SETTLE_DELAY = 250;
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
   * 加载在线图片（三级缓存：内存->磁盘->网络）
   */
  public async load(url: string, options?: OnlineLoadOptions): Promise<image.PixelMap | null> {
    const cacheKey = this.generateCacheKey(url, options);
    const priority = options?.priority || 1;
    
    // 1. 检查内存缓存

    const cached = this.getFromCache(cacheKey);
    if (cached) {
      logger.info(TAG, `✅ 内存缓存命中: ${url.substring(0, 80)}`);
      return cached;
    }
    
    // 2. 检查磁盘缓存（仅在已初始化时）
    try {
      const diskCache = DiskCacheManager.getInstance();
      // 检查是否已初始化，避免警告日志泛滥
      if (diskCache.isInitialized()) {
          const diskCached = await diskCache.get(this.buildDiskCacheUrl(url, options));

        if (diskCached) {
          logger.info(TAG, `✅ 磁盘缓存命中: ${url.substring(0, 80)}`);
          // 存入内存缓存
          this.putToCache(cacheKey, diskCached);
          return diskCached;
        }
      }
    } catch (error) {
      logger.debug(TAG, `磁盘缓存读取失败: ${String(error)}`);
    }
    
    // 3. [修复] 检查是否已在加载中
    if (this.loadingUrls.has(url)) {
      logger.debug(TAG, `URL已在加载队列中，等待现有加载完成: ${url.substring(0, 80)}`);
      // 等待现有加载完成，然后从缓存返回
      return this.waitForLoading(url, options);

    }
    
    // 4. 标记为正在加载
    this.loadingUrls.add(url);
    
    // 4. 加入请求队列
    return new Promise<image.PixelMap | null>((resolve, reject) => {
      const request: QueuedRequest = {
        url: url,
        options: options || {} as OnlineLoadOptions,
        priority: priority,
        resolve: resolve,
        reject: reject,
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
   * [新增] 等待URL加载完成
   */
  private async waitForLoading(url: string, options?: OnlineLoadOptions): Promise<image.PixelMap | null> {
    const maxWaitTime = 30000; // 最多等待30秒
    const checkInterval = 100; // 每100ms检查一次
    const startTime = Date.now();
    const cacheKey = this.generateCacheKey(url, options);
    
    while (this.loadingUrls.has(url)) {
      if (Date.now() - startTime > maxWaitTime) {
        logger.warn(TAG, `等待URL加载超时: ${url.substring(0, 80)}`);
        return null;
      }
      
      // 等待100ms后再检查
      await new Promise<void>((resolve) => setTimeout(resolve, checkInterval));
      
      // 检查缓存是否已更新
      const cached = this.getFromCache(cacheKey);
      if (cached) {
        return cached;
      }
    }
    
    // 加载完成，从缓存返回
    return this.getFromCache(cacheKey);
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
      // 【修复】移除请求间隔限制，10个并发本身就是限流措施
      // await this.waitForInterval();
      
      // 执行HTTP请求
      const pixelMap = await this.httpRequest(request.url, request.options);
      
      if (pixelMap) {
        // 存入内存缓存
        this.putToCache(this.generateCacheKey(request.url, request.options), pixelMap);
        
        // [新增] 存入磁盘缓存（仅在已初始化时）
        try {
          const diskCache = await this.getDiskCacheForRequest(request.options);
          if (diskCache && diskCache.isInitialized()) {
            const diskCacheUrl = this.buildDiskCacheUrl(request.url, request.options);
            await diskCache.put(diskCacheUrl, pixelMap);
            logger.debug(TAG, `已保存到磁盘缓存: ${request.url.substring(0, 80)}`);

            // [P1] 缓存状态写库异步批量化，避免阻塞主加载链路
            this.syncCacheStatusToDatabaseAsync(diskCacheUrl, diskCache);
          }
        } catch (error) {
          logger.warn(TAG, `保存到磁盘缓存失败: ${String(error)}`);
        }

        
        request.resolve(pixelMap);
        
        // [修复] 加载成功，从loadingUrls中移除
        this.loadingUrls.delete(request.url);
      } else {
        request.resolve(null);
        
        // [修复] 加载失败，从loadingUrls中移除
        this.loadingUrls.delete(request.url);
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
        
        // [修复] 最终失败，从loadingUrls中移除
        this.loadingUrls.delete(request.url);
      }
    } finally {
      this.activeRequests--;
      
      // 继续处理队列
      this.processQueue();
    }
  }

  private async getDiskCacheForRequest(_options?: OnlineLoadOptions): Promise<DiskCacheManager | null> {
    return DiskCacheManager.getInstance();
  }

  private buildDiskCacheUrl(url: string, options?: OnlineLoadOptions): string {
    if (!this.isPhotos18Request(options || {} as OnlineLoadOptions, url)) {
      return url;
    }
    const partition = this.resolveCachePartition(options, url);
    return `${url}#cache_partition=${partition}`;
  }

  private resolveCachePartition(options?: OnlineLoadOptions, url?: string): string {
    const explicitPartition = options?.partitionKey;
    if (explicitPartition && explicitPartition.length > 0) {
      return explicitPartition;
    }
    const headerPartition = options?.headers?.cachePartition;
    if (headerPartition && headerPartition.length > 0) {
      return headerPartition;
    }
    if (url && url.includes('/cover/')) {
      return 'detail-cover';
    }
    return 'default';
  }

  private syncCacheStatusToDatabaseAsync(url: string, diskCache: DiskCacheManager): void {

    (async () => {
      try {
        const filePath = await diskCache.getCacheFilePath(url);
        const fileSize = await diskCache.getCacheFileSize(url);

        if (filePath && fileSize > 0) {
          this.enqueueCacheStatusUpdate(url, filePath, fileSize);
        }
      } catch (error) {
        logger.warn(TAG, `准备缓存状态同步失败: ${String(error)}`);
      }
    })().catch((error: Error) => {
      logger.warn(TAG, `异步缓存状态同步失败: ${String(error)}`);
    });
  }

  private enqueueCacheStatusUpdate(imageUrl: string, localPath: string, fileSize: number): void {
    this.pendingCacheStatusUpdates.set(imageUrl, { localPath, fileSize });
    this.scheduleCacheStatusFlush();
  }

  private scheduleCacheStatusFlush(): void {
    if (this.cacheStatusFlushTimer !== null) {
      return;
    }

    this.cacheStatusFlushTimer = setTimeout(() => {
      this.cacheStatusFlushTimer = null;
      this.flushCacheStatusUpdates().catch((error: Error) => {
        logger.warn(TAG, `批量同步缓存状态到数据库失败: ${String(error)}`);
      });
    }, this.CACHE_STATUS_FLUSH_DELAY) as number;
  }

  private async flushCacheStatusUpdates(): Promise<void> {
    if (this.isFlushingCacheStatusUpdates || this.pendingCacheStatusUpdates.size === 0) {
      return;
    }

    this.isFlushingCacheStatusUpdates = true;
    const updates: Array<CacheStatusUpdatePayload> = [];
    this.pendingCacheStatusUpdates.forEach((value, imageUrl) => {
      updates.push({
        imageUrl,
        localPath: value.localPath,
        fileSize: value.fileSize
      });
    });
    this.pendingCacheStatusUpdates.clear();

    try {
      const dataManager = DataManager.getInstance();
      await dataManager.batchUpdateOnlinePageCacheStatus(updates);
      logger.debug(TAG, `Flushed cache status updates: count=${updates.length}`);
      logger.debug(TAG, `已批量同步缓存状态到数据库: ${updates.length}条`);
    } catch (error) {
      logger.warn(TAG, `批量同步缓存状态到数据库失败: ${String(error)}`);
    } finally {
      this.isFlushingCacheStatusUpdates = false;
      if (this.pendingCacheStatusUpdates.size > 0) {
        this.scheduleCacheStatusFlush();
      }
    }
  }

  /**
   * HTTP请求
   */
  private async httpRequest(url: string, options: OnlineLoadOptions): Promise<image.PixelMap | null> {
    // 首先尝试原始URL
    try {
      return await this.doHttpRequest(url, options);
    } catch (error) {
      const errObj = error as Object;
      const errCode = (errObj as Record<string, Object>)['code'];
      const errMsg = error instanceof Error ? error.message : String(error);
      
      if (this.isPhotos18Request(options, url) && errMsg.includes('HTTP请求失败: 403')) {
        logger.warn(TAG, `Photos18图片请求403，尝试刷新Cookie后重试: ${url.substring(0, 80)}`);
        const recovered = await this.retryPhotos18WithFreshCookie(url, options);
        if (recovered) {
          return recovered;
        }
      }
      
      // 如果是SSL错误(2300060)且URL是HTTPS，尝试降级为HTTP
      if (this.isRmcdnRequest(url) && this.isHttp403Error(errMsg)) {
        logger.warn(TAG, `rmcdn鍥剧墖HTTP 403锛屽皾璇昗ebView鍏滃簳鍔犺浇: ${url.substring(0, 80)}`);
        const recovered = await this.retryRmcdnWithWebView(url, options);
        if (recovered) {
          return recovered;
        }
      }

      if (errCode === 2300060 && url.startsWith('https://')) {
        const httpUrl = url.replace('https://', 'http://');
        logger.info(TAG, `SSL错误，尝试HTTP降级: ${httpUrl.substring(0, 80)}`);
        
        try {
          return await this.doHttpRequest(httpUrl, options);
        } catch (retryError) {
          // HTTP降级也失败，抛出原始错误
          logger.warn(TAG, `HTTP降级也失败: ${httpUrl.substring(0, 80)}`);
          throw error as Error;
        }
      }
      
      throw error as Error;
    }
  }

  private isPhotos18Request(options: OnlineLoadOptions, url: string): boolean {
    if (url.includes('photos18.com')) {
      return true;
    }
    const sourceId = options.sourceId;
    if (!sourceId) {
      return false;
    }
    const headers = options.headers;
    if (headers && headers.referer && headers.referer.includes('photos18.com')) {
      return true;
    }
    return false;
  }

  private async retryPhotos18WithFreshCookie(url: string, options: OnlineLoadOptions): Promise<image.PixelMap | null> {
    const sourceId = options.sourceId;
    if (!sourceId) {
      return null;
    }
    try {
      this.clearCookieCache(sourceId);
      const cookieManager = CookieManager.getInstance();
      const freshCookie = await cookieManager.getCookieString(sourceId);
      if (!freshCookie || freshCookie.length === 0) {
        logger.warn(TAG, 'Photos18 refresh cookie returned empty, skip retry');
        /*
        logger.warn(TAG, 'Photos18刷新Cookie后仍为空，放弃重试');
        return null;
      }
        */
        return null;
      }
      const retriedHeaders: RequestHeaders = {
        userAgent: options.headers?.userAgent,
        accept: options.headers?.accept,
        referer: options.headers?.referer,
        origin: options.headers?.origin,
        cookie: freshCookie,
        authorization: options.headers?.authorization,
        acceptLanguage: options.headers?.acceptLanguage,
        cacheControl: options.headers?.cacheControl,
        pragma: options.headers?.pragma,
        secFetchDest: options.headers?.secFetchDest,
        secFetchMode: options.headers?.secFetchMode,
        secFetchSite: options.headers?.secFetchSite
      };
      const retriedOptions: OnlineLoadOptions = {
        width: options.width,
        height: options.height,
        headers: retriedHeaders,
        sourceId: options.sourceId,
        priority: options.priority,
        partitionKey: options.partitionKey
      };

      return await this.doHttpRequest(url, retriedOptions);
    } catch (error) {
      logger.warn(TAG, `Photos18刷新Cookie重试失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 执行HTTP请求（内部方法）
   */
  private isRmcdnRequest(url: string): boolean {
    return url.includes('rmcdn');
  }

  private isHttp403Error(message: string): boolean {
    return message.includes('403');
  }

  private async retryRmcdnWithWebView(url: string, options: OnlineLoadOptions): Promise<image.PixelMap | null> {
    const fallbackSourceId = `${this.rmcdnFallbackPrefix}_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
    const controller = new webview.WebviewController();
    const headers = await this.buildHeaders(url, options);
    const userAgent = headers.userAgent ? headers.userAgent : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
    const config: WebViewSourceConfig = {
      sourceId: fallbackSourceId,
      userAgent: userAgent,
      enableJavaScript: true,
      enableImages: true,
      cookiePolicy: 'accept_all',
      timeout: this.TIMEOUT
    };

    let waiter: RmcdnWebViewWaiter | null = null;
    const pageLoadPromise = new Promise<void>((resolve, reject) => {
      waiter = { resolve: resolve, reject: reject };
    });
    const callbacks: WebViewEventCallbacks = {
      onPageEnd: (_loadedUrl: string) => {
        if (waiter) {
          waiter.resolve();
          waiter = null;
        }
      },
      onError: (error: string) => {
        if (waiter) {
          waiter.reject(new Error(error));
          waiter = null;
        }
      }
    };

    GlobalWebViewContainer.addWebView(fallbackSourceId, controller, config, callbacks, 'about:blank');

    try {
      await this.loadRmcdnUrlWithRetry(controller, url, headers, userAgent);
      await this.waitForPromiseWithTimeout(pageLoadPromise, this.RMCDN_WEBVIEW_LOAD_TIMEOUT, 'rmcdn WebView load timeout');
      await this.delay(this.RMCDN_WEBVIEW_SETTLE_DELAY);
      const imageBuffer = await this.extractRmcdnArrayBuffer(controller);
      const pixelMap = await this.createPixelMapFromBuffer(imageBuffer, options);
      logger.info(TAG, `rmcdn WebView鍏滃簳鍔犺浇鎴愬姛: bytes=${imageBuffer.byteLength}`);
      return pixelMap;
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `rmcdn WebView鍏滃簳鍔犺浇澶辫触: ${errMsg}`);
      return null;
    } finally {
      try {
        controller.loadUrl('about:blank');
      } catch (_loadBlankError) {
      }
      GlobalWebViewContainer.removeWebView(fallbackSourceId);
    }
  }

  private async loadRmcdnUrlWithRetry(
    controller: webview.WebviewController,
    url: string,
    headers: HttpHeadersObject,
    userAgent: string
  ): Promise<void> {
    const webHeaders = this.buildWebHeaders(headers);
    let attempt = 0;
    let lastError: Error | null = null;

    while (attempt < this.RMCDN_WEBVIEW_ATTACH_RETRIES) {
      try {
        controller.setCustomUserAgent(userAgent);
        if (webHeaders.length > 0) {
          controller.loadUrl(url, webHeaders);
        } else {
          controller.loadUrl(url);
        }
        return;
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        attempt = attempt + 1;
        await this.delay(this.RMCDN_WEBVIEW_ATTACH_DELAY);
      }
    }

    if (lastError) {
      throw lastError;
    }
    throw new Error('rmcdn WebView loadUrl failed');
  }

  private buildWebHeaders(headers: HttpHeadersObject): Array<webview.WebHeader> {
    const result: Array<webview.WebHeader> = [];
    const pairs: Array<[string, string | undefined]> = [
      ['User-Agent', headers.userAgent],
      ['Origin', headers.origin],
      ['Accept', headers.accept],
      ['Referer', headers.referer],
      ['Cookie', headers.cookie],
      ['Authorization', headers.authorization],
      ['Accept-Language', headers.acceptLanguage],
      ['Cache-Control', headers.cacheControl],
      ['Pragma', headers.pragma],
      ['Sec-Fetch-Dest', headers.secFetchDest],
      ['Sec-Fetch-Mode', headers.secFetchMode],
      ['Sec-Fetch-Site', headers.secFetchSite]
    ];
    let index = 0;
    while (index < pairs.length) {
      const pair = pairs[index];
      const headerValue = pair[1];
      if (headerValue && headerValue.length > 0) {
        result.push({
          headerKey: pair[0],
          headerValue: headerValue
        });
      }
      index = index + 1;
    }
    return result;
  }

  private async waitForPromiseWithTimeout(task: Promise<void>, timeoutMs: number, message: string): Promise<void> {
    let timeoutId: number | null = null;
    return await new Promise<void>((resolve, reject) => {
      timeoutId = setTimeout(() => {
        reject(new Error(message));
      }, timeoutMs);

      task.then(() => {
        if (timeoutId !== null) {
          clearTimeout(timeoutId);
        }
        resolve();
      }).catch((error: Error) => {
        if (timeoutId !== null) {
          clearTimeout(timeoutId);
        }
        reject(error);
      });
    });
  }

  private async extractRmcdnArrayBuffer(controller: webview.WebviewController): Promise<ArrayBuffer> {
    const script = `
      (() => {
        const imageElement = document.images && document.images.length > 0 ? document.images[0] : null;
        let requestUrl = '';
        if (imageElement && imageElement.src) {
          requestUrl = String(imageElement.src);
        } else if (window && window.location && window.location.href) {
          requestUrl = String(window.location.href);
        }
        if (!requestUrl) {
          throw new Error('rmcdn request url missing');
        }
        const xhr = new XMLHttpRequest();
        xhr.open('GET', requestUrl, false);
        xhr.responseType = 'arraybuffer';
        xhr.send(null);
        if (xhr.status >= 400) {
          throw new Error('rmcdn xhr failed with status ' + String(xhr.status));
        }
        if (!xhr.response) {
          throw new Error('rmcdn xhr returned empty buffer');
        }
        return xhr.response;
      })();
    `;
    const jsResult = await controller.runJavaScriptExt(script);
    const resultType = jsResult.getType();
    if (resultType === webview.JsMessageType.ARRAY_BUFFER) {
      return jsResult.getArrayBuffer();
    }
    if (resultType === webview.JsMessageType.STRING) {
      throw new Error(`rmcdn WebView script returned string: ${jsResult.getString()}`);
    }
    const errorDescription = jsResult.getErrorDescription();
    if (errorDescription) {
      throw new Error(errorDescription);
    }
    throw new Error(`rmcdn WebView script returned unsupported type: ${resultType}`);
  }

  private async doHttpRequest(url: string, options: OnlineLoadOptions): Promise<image.PixelMap | null> {
    try {
      const httpRequest = http.createHttp();
      const startTs = Date.now();
      
      // 构建请求头
      const headers = await this.buildHeaders(url, options);
      
      logger.debug(TAG, `发起HTTP请求: url=${url}, timeout=${this.TIMEOUT}`);
      
      const requestOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: this.TIMEOUT,
        readTimeout: this.TIMEOUT,
        header: this.createRequestHeadersObject(headers) as Object,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      };
      
      // 发送请求
      const response = await httpRequest.request(url, requestOptions);
      
      if (response.responseCode === 200 && response.result) {
        const duration = Date.now() - startTs;
        const imageBuffer = response.result as ArrayBuffer;
        const bytesLen = imageBuffer.byteLength;
        
        logger.info(TAG, `HTTP响应成功: code=200, bytes=${bytesLen}, duration=${duration}ms`);
        
        // 检查是否需要解扰/解密
        let finalBuffer = imageBuffer;
        
        // 禁漫天堂图片解扰（检查URL是否包含media/photos）
        if (url.includes('media/photos')) {
          const imageInfo = JinmantiantangDescrambler.extractImageInfo(url);
          if (imageInfo !== null) {
            const descrambler = getJinmantiantangDescrambler();
            const params: JinmantiantangParameters = {
              aid: imageInfo.aid,
              imgIndex: imageInfo.imgIndex
            };
            
            // 检查是否需要解扰（aid >= 220980）
            if (descrambler.shouldDescramble(url, params)) {
              logger.info(TAG, `检测到禁漫天堂加扰图片，开始解扰: aid=${imageInfo.aid}, imgIndex=${imageInfo.imgIndex}`);
              try {
                finalBuffer = await descrambler.descramble(imageBuffer, params);
                logger.info(TAG, `禁漫天堂图片解扰完成，原始大小: ${imageBuffer.byteLength}, 解扰后: ${finalBuffer.byteLength}`);
              } catch (descrambleError) {
                const errMsg = descrambleError instanceof Error ? descrambleError.message : String(descrambleError);
                logger.error(TAG, `禁漫天堂图片解扰失败: ${errMsg}`);
                // 解扰失败时使用原始图片
                finalBuffer = imageBuffer;
              }
            }
          }
        }
        
        // Manwa图片AES解密
        if (url.endsWith('?v=20220724')) {
          logger.debug(TAG, `检测到加密图片，开始AES解密: ${url.substring(0, 80)}`);
          try {
            // 记录原始数据的前16字节（加密头）
            const encryptedView = new Uint8Array(imageBuffer);
            const encHeader = Array.from(encryptedView.slice(0, 16)).map(b => b.toString(16).padStart(2, '0')).join(' ');
            logger.debug(TAG, `加密数据头(hex): ${encHeader}`);
            
            finalBuffer = await this.decryptManwaImage(imageBuffer);
            
            // 记录解密后的前16字节（应该是WEBP文件头: RIFF....WEBP）
            const decryptedView = new Uint8Array(finalBuffer);
            const decHeader = Array.from(decryptedView.slice(0, 16)).map(b => b.toString(16).padStart(2, '0')).join(' ');
            logger.debug(TAG, `解密数据头(hex): ${decHeader}`);
            
            // 检查是否是有效的WEBP文件（RIFF开头）
            const isValidWebP = decryptedView[0] === 0x52 && decryptedView[1] === 0x49 && 
                               decryptedView[2] === 0x46 && decryptedView[3] === 0x46;
            logger.debug(TAG, `AES解密完成，解密后大小: ${finalBuffer.byteLength}, 是否有效WEBP: ${isValidWebP}`);
            
            if (!isValidWebP) {
              logger.warn(TAG, `解密后的数据不是有效的WEBP格式！前4字节: ${decHeader.substring(0, 11)}`);
            }
          } catch (decryptError) {
            logger.error(TAG, `AES解密失败: ${decryptError}`);
            throw new Error(`图片解密失败: ${decryptError}`);
          }
        }
        
        // 创建PixelMap
        const pixelMap = await this.createPixelMapFromBuffer(finalBuffer, options);
        /*
        let pixelMap: image.PixelMap | null = null;
        
        // 检查是否为AVIF格式，使用专用解码器
        if (isAvifFormat(finalBuffer)) {
          logger.info(TAG, `检测到AVIF格式图片，使用AVIF解码器`);
          const avifDecoder = AvifDecoder.getInstance();
          if (avifDecoder.isSupported()) {
            pixelMap = await avifDecoder.decode(finalBuffer);
            if (pixelMap) {
              logger.info(TAG, `AVIF解码成功`);
            } else {
              logger.warn(TAG, `AVIF解码失败，尝试系统解码器`);
            }
          } else {
            logger.warn(TAG, `AVIF解码器不可用（libavif未安装），尝试系统解码器`);
          }
        }
        
        // 如果AVIF解码失败或不是AVIF格式，使用系统解码器
        if (!pixelMap) {
          const imageSource = image.createImageSource(finalBuffer);
          const decodingOptions: image.DecodingOptions = {
            desiredSize: options.width && options.height ? 
              { width: options.width, height: options.height } : undefined,
            desiredPixelFormat: image.PixelMapFormat.RGBA_8888
          };
          
          pixelMap = await imageSource.createPixelMap(decodingOptions);
        }
        
        */
        httpRequest.destroy();
        return pixelMap;
        
      } else {
        const duration = Date.now() - startTs;
        logger.warn(TAG, `HTTP响应失败: code=${response.responseCode}, duration=${duration}ms`);
        throw new Error(`HTTP请求失败: ${response.responseCode}`);
      }
      
    } catch (error) {
      // 【修复】详细记录错误信息，包括错误码和完整URL
      // HarmonyOS的BusinessError对象包含code和message属性
      let errMsg = '';
      if (error instanceof Error) {
        errMsg = error.message;
      } else if (typeof error === 'object' && error !== null) {
        // 尝试提取message，如果是对象则序列化
        const msg = (error as Record<string, Object>)['message'];
        if (typeof msg === 'object') {
          try {
            errMsg = JSON.stringify(error as Object);
          } catch (e) {
            errMsg = String(error);
          }
        } else {
          errMsg = String(msg || error);
        }
      } else {
        errMsg = String(error);
      }

      const errCode = (error as Record<string, Object>)['code'];
      const errData = (error as Record<string, Object>)['data'];
      
      // 输出完整错误信息
      logger.error(TAG, `HTTP请求异常: message=${errMsg}, code=${errCode}, data=${errData}, url=${url}`);
      
      // 重新抛出错误
      throw new Error(`${errMsg} (code=${errCode})`);
    }
  }

  /**
   * 构建请求头
   */
  private async createPixelMapFromBuffer(buffer: ArrayBuffer, options: OnlineLoadOptions): Promise<image.PixelMap | null> {
    let pixelMap: image.PixelMap | null = null;

    if (isAvifFormat(buffer)) {
      logger.info(TAG, '妫€娴嬪埌AVIF鏍煎紡鍥剧墖锛屼娇鐢ˋVIF瑙ｇ爜鍣?');
      const avifDecoder = AvifDecoder.getInstance();
      if (avifDecoder.isSupported()) {
        pixelMap = await avifDecoder.decode(buffer);
        if (pixelMap) {
          logger.info(TAG, 'AVIF瑙ｇ爜鎴愬姛');
        } else {
          logger.warn(TAG, 'AVIF瑙ｇ爜澶辫触锛屽皾璇曠郴缁熻В鐮佸櫒');
        }
      } else {
        logger.warn(TAG, 'AVIF瑙ｇ爜鍣ㄤ笉鍙敤锛坙ibavif鏈畨瑁咃級锛屽皾璇曠郴缁熻В鐮佸櫒');
      }
    }

    if (!pixelMap) {
      const imageSource = image.createImageSource(buffer);
      const decodingOptions: image.DecodingOptions = {
        desiredSize: options.width && options.height ?
          { width: options.width, height: options.height } : undefined,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      };
      pixelMap = await imageSource.createPixelMap(decodingOptions);
    }

    return pixelMap;
  }

  private createRequestHeadersObject(headers: HttpHeadersObject): HttpRequestHeadersObject {
    const requestHeaders: HttpRequestHeadersObject = {
      'User-Agent': headers.userAgent,
      'Origin': headers.origin,
      'Accept': headers.accept,
      'Referer': headers.referer,
      'Cookie': headers.cookie,
      'Authorization': headers.authorization,
      'Accept-Language': headers.acceptLanguage,
      'Cache-Control': headers.cacheControl,
      'Pragma': headers.pragma,
      'Sec-Fetch-Dest': headers.secFetchDest,
      'Sec-Fetch-Mode': headers.secFetchMode,
      'Sec-Fetch-Site': headers.secFetchSite
    };
    return requestHeaders;
  }

  private async buildHeaders(url: string, options: OnlineLoadOptions): Promise<HttpHeadersObject> {
    await this.getDiskCacheForRequest(options);

    const defaultUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
    const defaultAccept = 'image/avif,image/webp,image/png,image/jpeg;q=0.9,*/*;q=0.5';
    const defaultLang = 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7';
    
    // 优先使用传入的UA，否则通过UserAgentManager获取（支持图源级别和全局设置）
    let ua = options.headers?.userAgent || '';
    if (!ua && options.sourceId) {
      ua = await UserAgentManager.getInstance().getUserAgent(options.sourceId);
      logger.info(TAG, `通过UserAgentManager获取UA: sourceId=${options.sourceId}, ua=${ua.substring(0, 50)}...`);
    }
    if (!ua) {
      ua = defaultUa;
      logger.debug(TAG, `使用默认UA`);
    }
    const accept = options.headers?.accept || defaultAccept;
    let referer = options.headers?.referer || '';
    let origin = options.headers?.origin || '';
    
    // 自动为特定CDN添加Referer（解决防盗链和SSL问题）
    if (!referer && (url.includes('amh1234.wszwhg.net') || url.includes('gmh1234.wszwhg.net'))) {
      referer = 'https://b.amh1234.com/';
      origin = 'https://b.amh1234.com';
    }
    
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
      userAgent: ua,
      origin: origin || (referer || undefined),
      accept: accept,
      referer: referer || undefined,
      cookie: cookie || undefined,
      authorization: authorization || undefined,
      acceptLanguage: acceptLanguage || undefined,
      cacheControl: cacheControl || undefined,
      pragma: pragma || undefined,
      secFetchDest: secFetchDest || undefined,
      secFetchMode: secFetchMode || undefined,
      secFetchSite: secFetchSite || undefined
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

  public clearCookieCache(sourceId?: number): void {
    if (sourceId !== undefined) {
      this.cookieCache.delete(sourceId);
      logger.debug(TAG, `清除在线图片Cookie缓存: sourceId=${sourceId}`);
      return;
    }
    this.cookieCache.clear();
    logger.debug(TAG, '清除全部在线图片Cookie缓存');
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
  private async delay(ms: number): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  private sortQueue(): void {
    this.requestQueue.sort((a, b) => b.priority - a.priority);
  }

  /**
   * 生成缓存键
   */
  private generateCacheKey(url: string, options?: OnlineLoadOptions): string {
    let base = url;
    if (options?.partitionKey && options.partitionKey.length > 0) {
      base = `${base}#p=${options.partitionKey}`;
    }
    if (options?.headers?.cachePartition && options.headers.cachePartition.length > 0) {
      base = `${base}#hp=${options.headers.cachePartition}`;
    }
    if (options?.headers?.referer && options.headers.referer.length > 0) {
      base = `${base}#r=${options.headers.referer}`;
    }
    // 使用URL的hash作为缓存键
    let hash = 0;
    for (let i = 0; i < base.length; i++) {
      const char = base.charCodeAt(i);
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

  /**
   * 解密 Manwa 加密图片
   * 使用 AES-CBC 解密，密钥和IV都是 "my2ecret782ecret"
   */
  private async decryptManwaImage(encryptedBuffer: ArrayBuffer): Promise<ArrayBuffer> {
    const keyStr = 'my2ecret782ecret';
    const keyData = this.stringToUint8Array(keyStr);
    
    // 创建对称密钥生成器
    const symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
    const keyBlob: cryptoFramework.DataBlob = { data: keyData };
    const symKey = await symKeyGenerator.convertKey(keyBlob);
    
    // 创建解密器 AES-CBC-NoPadding
    const cipher = cryptoFramework.createCipher('AES128|CBC|NoPadding');
    
    // 初始化解密器，IV 同密钥
    const ivBlob: cryptoFramework.DataBlob = { data: keyData };
    const params: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: ivBlob
    };
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
    
    // 执行解密
    const encryptedData: cryptoFramework.DataBlob = { data: new Uint8Array(encryptedBuffer) };
    const decryptedBlob = await cipher.doFinal(encryptedData);
    
    if (!decryptedBlob || !decryptedBlob.data) {
      throw new Error('解密结果为空');
    }
    
    // 【修复】正确复制解密数据到新的 ArrayBuffer
    // Uint8Array.buffer 可能包含额外的偏移量，需要创建精确大小的新 buffer
    const decryptedData = decryptedBlob.data;
    const resultBuffer = new ArrayBuffer(decryptedData.length);
    const resultView = new Uint8Array(resultBuffer);
    resultView.set(decryptedData);
    
    return resultBuffer;
  }

  /**
   * 字符串转 Uint8Array
   */
  private stringToUint8Array(str: string): Uint8Array {
    const arr = new Uint8Array(str.length);
    for (let i = 0; i < str.length; i++) {
      arr[i] = str.charCodeAt(i);
    }
    return arr;
  }
}
