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
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { DiskCacheManager } from './DiskCacheManager';
import { DataManager } from '../Data/DataManager';
import { JinmantiantangDescrambler, JinmantiantangParameters } from '../ImageProcessing/JinmantiantangDescrambler';
import { UserAgentManager } from '../Managers/UserAgentManager';

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
  private readonly MAX_CONCURRENT = 10;  // 【修复】提升到10个并发，加快封面加载速度
  
  // [修复] 正在加载的URL集合，用于去重
  private loadingUrls = new Set<string>();
  
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
   * 加载在线图片（三级缓存：内存->磁盘->网络）
   */
  public async load(url: string, options?: OnlineLoadOptions): Promise<image.PixelMap | null> {
    const cacheKey = this.generateCacheKey(url);
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
        const diskCached = await diskCache.get(url);
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
      return this.waitForLoading(url);
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
  private async waitForLoading(url: string): Promise<image.PixelMap | null> {
    const maxWaitTime = 30000; // 最多等待30秒
    const checkInterval = 100; // 每100ms检查一次
    const startTime = Date.now();
    
    while (this.loadingUrls.has(url)) {
      if (Date.now() - startTime > maxWaitTime) {
        logger.warn(TAG, `等待URL加载超时: ${url.substring(0, 80)}`);
        return null;
      }
      
      // 等待100ms后再检查
      await new Promise<void>((resolve) => setTimeout(resolve, checkInterval));
      
      // 检查缓存是否已更新
      const cached = this.getFromCache(this.generateCacheKey(url));
      if (cached) {
        return cached;
      }
    }
    
    // 加载完成，从缓存返回
    return this.getFromCache(this.generateCacheKey(url));
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
        this.putToCache(this.generateCacheKey(request.url), pixelMap);
        
        // [新增] 存入磁盘缓存（仅在已初始化时）
        try {
          const diskCache = DiskCacheManager.getInstance();
          if (diskCache.isInitialized()) {
            await diskCache.put(request.url, pixelMap);
            logger.debug(TAG, `已保存到磁盘缓存: ${request.url.substring(0, 80)}`);
          }
          
          // [新增] 同步缓存状态到数据库
          try {
            const filePath = await diskCache.getCacheFilePath(request.url);
            const fileSize = await diskCache.getCacheFileSize(request.url);
            
            if (filePath && fileSize > 0) {
              const dataManager = DataManager.getInstance();
              await dataManager.updateOnlinePageCacheStatus(request.url, filePath, fileSize);
              logger.debug(TAG, `已同步缓存状态到数据库: ${request.url.substring(0, 80)}`);
            }
          } catch (dbError) {
            logger.warn(TAG, `同步缓存状态到数据库失败: ${String(dbError)}`);
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
      
      // 如果是SSL错误(2300060)且URL是HTTPS，尝试降级为HTTP
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

  /**
   * 执行HTTP请求（内部方法）
   */
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
        const imageSource = image.createImageSource(finalBuffer);
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
            errMsg = JSON.stringify(msg);
          } catch (e) {
            errMsg = '[object Object]';
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
  private async buildHeaders(url: string, options: OnlineLoadOptions): Promise<HttpHeadersObject> {
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
