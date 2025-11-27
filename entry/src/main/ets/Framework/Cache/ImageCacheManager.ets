// 文件路径: src/main/ets/Framework/Cache/ImageCacheManager.ets
/**
 * 图片缓存管理器
 * 基于ImageKnife实现三级缓存机制（内存缓存、磁盘缓存、网络加载）
 */

import { image } from '@kit.ImageKit';
import { logger } from '../../Utils/Logger';
import { SandboxManager } from '../Storage/SandboxManager';
import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import { CacheStats, MemoryCacheStats, DiskCacheStats } from '../Data/DataManager';
import CookieManager from '../Managers/CookieManager';
import { PermanentImageCacheManager } from './PermanentImageCacheManager';
import { OnlineImageLoader, OnlineLoadOptions, RequestHeaders as OnlineRequestHeaders } from './OnlineImageLoader';
import fs from '@ohos.file.fs';

const TAG = 'ImageCacheManager';

// 内存缓存配置接口
export interface MemoryCacheConfig {
  maxSize: number;          // 最大内存缓存大小（字节）
  maxCount: number;         // 最大缓存图片数量
  evictionPolicy: 'LRU' | 'LFU';  // 淘汰策略
}

// 磁盘缓存配置接口
export interface DiskCacheConfig {
  maxSize: number;          // 最大磁盘缓存大小（字节）
  maxAge: number;           // 最大缓存时间（毫秒）
  compressionQuality: number; // 压缩质量 0-100
}

// 网络配置接口
export interface NetworkConfig {
  timeout: number;          // 网络超时时间（毫秒）
  retryCount: number;       // 重试次数
  retryDelay: number;       // 重试延迟（毫秒）
}

export interface ImageCacheConfig {
  // 内存缓存配置
  memoryCache: MemoryCacheConfig;
  
  // 磁盘缓存配置
  diskCache: DiskCacheConfig;
  
  // 网络配置
  network: NetworkConfig;
}

export interface CacheEntry {
  key: string;
  pixelMap: image.PixelMap;
  size: number;
  accessTime: number;
  accessCount: number;
  createTime: number;
}

export interface DiskCacheInfo {
  key: string;
  filePath: string;
  size: number;
  createTime: number;
  lastAccessTime: number;
}

export interface CookieCacheEntry {
  cookie: string;
  timestamp: number;
}

export enum ImageLoadingMethod {
  HTTP,
  WEBVIEW
}

export interface LoadOptions {
  width?: number;
  height?: number;
  quality?: number;
  placeholder?: image.PixelMap;
  errorImage?: image.PixelMap;
  skipMemoryCache?: boolean;
  skipDiskCache?: boolean;
  forceRefresh?: boolean;
  headers?: RequestHeaders;
  sourceId?: number;
  loadingMethod?: ImageLoadingMethod;
  partitionKey?: string;
  // 永久缓存相关参数
  mangaId?: string;
  chapterId?: string;
  pageIndex?: number;
  // 在线图片加载优先级
  priority?: number;  // 10=当前页，5=下一页，3=下下页，1=其他
  // 内容类型（用于判断是否为在线漫画）
  contentType?: string;
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


export class ImageCacheManager {
  private static instance: ImageCacheManager | null = null;
  private sandboxManager: SandboxManager;
  
  // 内存缓存
  private memoryCache = new Map<string, CacheEntry>();
  private memoryCacheSize = 0;
  
  // 磁盘缓存索引
  private diskCacheIndex = new Map<string, DiskCacheInfo>();
  private diskCacheSize = 0; // 追踪磁盘缓存总大小，避免频繁扫描目录
  
  // 正在加载的图片（防止重复加载）
  private loadingTasks = new Map<string, Promise<image.PixelMap | null>>();
  
  // 优化：Cookie内存缓存（避免每次请求都查询数据库）
  private cookieCache = new Map<number, CookieCacheEntry>();
  private readonly COOKIE_CACHE_TTL = 5 * 60 * 1000; // 5分钟过期
  
  // 默认配置
  private config: ImageCacheConfig = {
    memoryCache: {
      maxSize: 100 * 1024 * 1024,  // 100MB
      maxCount: 200,
      evictionPolicy: 'LRU'
    } as MemoryCacheConfig,
    diskCache: {
      maxSize: 500 * 1024 * 1024,  // 500MB
      maxAge: 7 * 24 * 60 * 60 * 1000,  // 7天
      compressionQuality: 85
    } as DiskCacheConfig,
    network: {
      timeout: 12000,  // 优化：12秒超时，快速失败
      retryCount: 3,
      retryDelay: 500  // 优化：500ms重试延迟
    } as NetworkConfig
  };

  private constructor() {
    this.sandboxManager = SandboxManager.getInstance();
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): ImageCacheManager {
    if (!ImageCacheManager.instance) {
      ImageCacheManager.instance = new ImageCacheManager();
    }
    return ImageCacheManager.instance;
  }

  /**
   * 初始化缓存管理器
   */
  public async initialize(config?: Partial<ImageCacheConfig>): Promise<void> {
    try {
      // 合并配置
      if (config) {
        this.config = this.mergeConfig(this.config, config);
      }
      
      // 初始化磁盘缓存索引
      await this.initializeDiskCacheIndex();
      
      // 启动定期清理
      this.startCleanupTimer();
      
      logger.info(TAG, '图片缓存管理器初始化完成');
    } catch (error) {
      logger.error(TAG, '图片缓存管理器初始化失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 加载图片（三级缓存）
   */
  public async loadImage(url: string, options?: LoadOptions): Promise<image.PixelMap | null> {
    try {
      const cacheKey = this.generateCacheKey(url, options);
      
      // 检查是否正在加载
      if (this.loadingTasks.has(cacheKey)) {
        return await this.loadingTasks.get(cacheKey)!;
      }
      
      // 创建加载任务
      const loadTask = this.performImageLoad(url, cacheKey, options);
      this.loadingTasks.set(cacheKey, loadTask);
      
      try {
        const result = await loadTask;
        return result;
      } finally {
        this.loadingTasks.delete(cacheKey);
      }
      
    } catch (error) {
      logger.error(TAG, `加载图片失败: ${url}` + String(error));
      return options?.errorImage || null;
    }
  }

  /**
   * 执行图片加载（四级缓存逻辑）
   */
  private async performImageLoad(
    url: string,
    cacheKey: string,
    options?: LoadOptions
  ): Promise<image.PixelMap | null> {
    try {
      // 判断是否为在线漫画
      const isOnlineManga = this.isOnlineManga(options);
      
      // 在线漫画：使用OnlineImageLoader（跳过磁盘缓存）
      if (isOnlineManga) {
        logger.debug(TAG, `使用OnlineImageLoader加载在线图片: ${url.substring(0, 80)}`);
        const onlineLoader = OnlineImageLoader.getInstance();
        
        // 构建OnlineLoadOptions（类型兼容）
        let onlineHeaders: OnlineRequestHeaders | undefined = undefined;
        if (options?.headers) {
          onlineHeaders = {
            userAgent: options.headers.userAgent,
            accept: options.headers.accept,
            referer: options.headers.referer,
            origin: options.headers.origin,
            cookie: options.headers.cookie,
            authorization: options.headers.authorization,
            acceptLanguage: options.headers.acceptLanguage,
            cacheControl: options.headers.cacheControl,
            pragma: options.headers.pragma,
            secFetchDest: options.headers.secFetchDest,
            secFetchMode: options.headers.secFetchMode,
            secFetchSite: options.headers.secFetchSite
          };
        }
        
        const onlineOptions: OnlineLoadOptions = {
          width: options?.width,
          height: options?.height,
          headers: onlineHeaders,
          sourceId: options?.sourceId,
          priority: options?.priority || 1
        };
        return await onlineLoader.load(url, onlineOptions);
      }
      
      // 本地/下载漫画：使用原有的四级缓存逻辑
      
      // 第一级：内存缓存
      if (!options?.skipMemoryCache && !options?.forceRefresh) {
        const memoryResult = this.getFromMemoryCache(cacheKey);
        if (memoryResult) {
          logger.debug(TAG, `内存缓存命中: ${url}`);
          return memoryResult;
        }
      }
      
      // 第二级：磁盘缓存（临时）
      if (!options?.skipDiskCache && !options?.forceRefresh) {
        const diskResult = await this.getFromDiskCache(cacheKey, options);
        if (diskResult) {
          logger.debug(TAG, `磁盘缓存命中: ${url}`);
          // 存入内存缓存
          if (!options?.skipMemoryCache) {
            await this.putToMemoryCache(cacheKey, diskResult);
          }
          return diskResult;
        }
      }
      
      // 第三级：永久缓存（如果启用了downloadWhileReading）
      if (this.shouldUsePermanentCache(options) && !options?.forceRefresh) {
        const permanentResult = await this.getFromPermanentCache(url, options!);
        if (permanentResult) {
          logger.debug(TAG, `永久缓存命中: ${url}`);
          // 存入内存缓存
          if (!options?.skipMemoryCache) {
            await this.putToMemoryCache(cacheKey, permanentResult);
          }
          return permanentResult;
        }
      }
      
      // 第四级：网络加载
      logger.debug(TAG, `网络加载: ${url}`);
      const networkResult = await this.loadFromNetwork(url, options);
      
      if (networkResult) {
        // 保存到永久缓存（如果启用）
        if (this.shouldUsePermanentCache(options)) {
          await this.saveToPermanentCache(url, networkResult, options!);
        }
        
        // 存入临时磁盘缓存
        if (!options?.skipDiskCache) {
          await this.putToDiskCache(cacheKey, networkResult, options);
        }
        
        // 存入内存缓存
        if (!options?.skipMemoryCache) {
          await this.putToMemoryCache(cacheKey, networkResult);
        }
      }
      
      return networkResult;
      
    } catch (error) {
      logger.error(TAG, `执行图片加载失败: ${url}` + String(error));
      throw error as Error;
    }
  }

  /**
   * 判断是否为在线漫画
   */
  private isOnlineManga(options?: LoadOptions): boolean {
    // 根据contentType判断
    if (options?.contentType === 'OnlineUndownloaded') {
      return true;
    }
    // 如果没有永久缓存参数，也认为是在线漫画
    if (!this.shouldUsePermanentCache(options)) {
      return true;
    }
    return false;
  }

  /**
   * 判断是否应该使用永久缓存
   */
  private shouldUsePermanentCache(options?: LoadOptions): boolean {
    return !!(
      options?.sourceId !== undefined &&
      options?.mangaId &&
      options?.chapterId &&
      options?.pageIndex !== undefined
    );
  }

  /**
   * 从永久缓存获取图片
   */
  private async getFromPermanentCache(
    url: string,
    options: LoadOptions
  ): Promise<image.PixelMap | null> {
    try {
      const permanentCache = PermanentImageCacheManager.getInstance();
      const cachedPath = await permanentCache.getCachedImagePath(
        options.sourceId!,
        options.mangaId!,
        options.chapterId!,
        options.pageIndex!,
        url
      );
      
      if (cachedPath) {
        return await this.loadImageFromFile(cachedPath);
      }
      
      return null;
    } catch (error) {
      logger.error(TAG, '从永久缓存加载失败', String(error));
      return null;
    }
  }

  /**
   * 保存到永久缓存
   */
  private async saveToPermanentCache(
    url: string,
    pixelMap: image.PixelMap,
    options: LoadOptions
  ): Promise<void> {
    try {
      const permanentCache = PermanentImageCacheManager.getInstance();
      
      // 将PixelMap转换为ArrayBuffer
      const imageData = await this.pixelMapToArrayBuffer(pixelMap);
      
      await permanentCache.saveImageToCache(
        options.sourceId!,
        options.mangaId!,
        options.chapterId!,
        options.pageIndex!,
        url,
        imageData
      );
      
      logger.debug(TAG, `已保存到永久缓存: ${url}`);
    } catch (error) {
      logger.warn(TAG, '保存到永久缓存失败', String(error));
    }
  }

  /**
   * 从文件加载PixelMap
   */
  private async loadImageFromFile(filePath: string): Promise<image.PixelMap | null> {
    try {
      const imageSourceApi = image.createImageSource(filePath);
      const pixelMap = await imageSourceApi.createPixelMap();
      return pixelMap;
    } catch (error) {
      logger.error(TAG, `从文件加载图片失败: ${filePath}`, String(error));
      return null;
    }
  }

  /**
   * PixelMap转ArrayBuffer
   */
  private async pixelMapToArrayBuffer(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
    try {
      const imagePackerApi = image.createImagePacker();
      const packOpts: image.PackingOption = { format: 'image/jpeg', quality: 95 };
      const data = await imagePackerApi.packing(pixelMap, packOpts);
      return data;
    } catch (error) {
      const errorMsg = `PixelMap转ArrayBuffer失败: ${error}`;
      logger.error(TAG, errorMsg);
      throw new Error(errorMsg);
    }
  }

  /**
   * 从内存缓存获取图片
   */
  private getFromMemoryCache(cacheKey: string): image.PixelMap | null {
    const entry = this.memoryCache.get(cacheKey);
    if (entry) {
      // 更新访问信息
      entry.accessTime = Date.now();
      entry.accessCount++;
      return entry.pixelMap;
    }
    return null;
  }

  /**
   * 存入内存缓存
   */
  private async putToMemoryCache(cacheKey: string, pixelMap: image.PixelMap): Promise<void> {
    try {
      const imageSize = await this.calculatePixelMapSize(pixelMap);
      
      // 检查是否需要清理内存缓存
      this.evictMemoryCacheIfNeeded(imageSize);
      
      const entry: CacheEntry = {
        key: cacheKey,
        pixelMap: pixelMap,
        size: imageSize,
        accessTime: Date.now(),
        accessCount: 1,
        createTime: Date.now()
      };
      
      this.memoryCache.set(cacheKey, entry);
      this.memoryCacheSize += imageSize;
      
      logger.debug(TAG, `存入内存缓存: ${cacheKey}, 大小: ${imageSize}`);
    } catch (error) {
      logger.error(TAG, '存入内存缓存失败' + String(error));
    }
  }

  /**
   * 从磁盘缓存获取图片
   */
  private async getFromDiskCache(cacheKey: string, options?: LoadOptions): Promise<image.PixelMap | null> {
    try {
      const cacheInfo = this.diskCacheIndex.get(cacheKey);
      if (!cacheInfo) {
        return null;
      }
      
      // 检查文件是否存在
      if (!await this.sandboxManager.exists(cacheInfo.filePath)) {
        this.diskCacheIndex.delete(cacheKey);
        return null;
      }
      
      // 检查是否过期
      const now = Date.now();
      if (now - cacheInfo.createTime > this.config.diskCache.maxAge) {
        await this.removeFromDiskCache(cacheKey);
        return null;
      }
      
      // 读取图片文件
      const imageBuffer = await this.sandboxManager.readFile(cacheInfo.filePath);
      const imageSource = image.createImageSource(imageBuffer);
      
      // 创建PixelMap
      const decodingOptions: image.DecodingOptions = {
        desiredSize: options?.width && options?.height ? 
          { width: options.width, height: options.height } : undefined,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      };
      
      const pixelMap = await imageSource.createPixelMap(decodingOptions);
      
      // 更新访问时间
      cacheInfo.lastAccessTime = now;
      
      return pixelMap;
      
    } catch (error) {
      logger.error(TAG, '从磁盘缓存获取图片失败' + String(error));
      return null;
    }
  }

  /**
   * 存入磁盘缓存
   */
  private async putToDiskCache(
    cacheKey: string,
    pixelMap: image.PixelMap,
    options?: LoadOptions
  ): Promise<void> {
    try {
      const coversDir = this.sandboxManager.getDirectory('covers');
      const fileName = `${cacheKey}.jpg`;
      const filePath = `${coversDir}/${fileName}`;
      
      // 将PixelMap转换为JPEG格式
      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: options?.quality || this.config.diskCache.compressionQuality
      };
      
      const imagePacker = image.createImagePacker();
      const imageBuffer = await imagePacker.packing(pixelMap, packOpts);
      
      // 写入文件
      await this.sandboxManager.writeFile(filePath, imageBuffer);
      
      // 更新索引
      const cacheInfo: DiskCacheInfo = {
        key: cacheKey,
        filePath: filePath,
        size: imageBuffer.byteLength,
        createTime: Date.now(),
        lastAccessTime: Date.now()
      };
      
      this.diskCacheIndex.set(cacheKey, cacheInfo);
      this.diskCacheSize += imageBuffer.byteLength; // 更新磁盘缓存大小
      
      // 检查磁盘缓存大小
      await this.evictDiskCacheIfNeeded();
      
      logger.debug(TAG, `存入磁盘缓存: ${cacheKey}, 路径: ${filePath}`);
      
    } catch (error) {
      logger.error(TAG, '存入磁盘缓存失败' + String(error));
    }
  }

  /**
   * 从网络加载图片
   */
  private async loadFromNetwork(url: string, options?: LoadOptions): Promise<image.PixelMap | null> {
    let retryCount = 0;
    const maxRetries = this.config.network.retryCount;
    
    while (retryCount <= maxRetries) {
      try {
        // 创建HTTP请求
        const httpRequest = http.createHttp();
        const startTs: number = Date.now();
        
        const defaultUa: string = 'HarmonyOS-Comic-Reader/1.0';
        const defaultAccept: string = 'image/avif,image/webp,image/png,image/jpeg;q=0.9,*/*;q=0.5';
        const defaultLang: string = 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7';
        const ua: string = options && options.headers && options.headers.userAgent ? String(options.headers.userAgent) : defaultUa;
        const acceptHdr: string = options && options.headers && options.headers.accept ? String(options.headers.accept) : defaultAccept;
        const refererHdr: string = options && options.headers && options.headers.referer ? String(options.headers.referer) : '';
        const originHdr: string = options && options.headers && options.headers.origin ? String(options.headers.origin) : '';
        
        // 优化：使用内存缓存获取Cookie，避免每次都查询数据库
        let cookieHdr: string = options && options.headers && options.headers.cookie ? String(options.headers.cookie) : '';
        if (cookieHdr.length === 0 && options && options.sourceId) {
          try {
            cookieHdr = await this.getCachedCookie(options.sourceId);
            if (cookieHdr.length > 0) {
              logger.debug(TAG, `图片请求获取Cookie: sourceId=${options.sourceId}, length=${cookieHdr.length}`);
            }
          } catch (e) {
            logger.warn(TAG, `图片请求获取Cookie失败: sourceId=${options.sourceId}, error=${String(e)}`);
          }
        }
        
        const authorizationHdr: string = options && options.headers && options.headers.authorization ? String(options.headers.authorization) : '';
        const acceptLanguageHdr: string = options && options.headers && options.headers.acceptLanguage ? String(options.headers.acceptLanguage) : defaultLang;
        const cacheControlHdr: string = options && options.headers && options.headers.cacheControl ? String(options.headers.cacheControl) : '';
        const pragmaHdr: string = options && options.headers && options.headers.pragma ? String(options.headers.pragma) : '';
        const secFetchDestHdr: string = options && options.headers && options.headers.secFetchDest ? String(options.headers.secFetchDest) : 'image';
        const secFetchModeHdr: string = options && options.headers && options.headers.secFetchMode ? String(options.headers.secFetchMode) : 'no-cors';
        let secFetchSiteHdr: string = 'same-origin';
        if (options && options.headers && options.headers.secFetchSite) {
          secFetchSiteHdr = String(options.headers.secFetchSite);
        } else {
          const urlHost: string = this.extractHost(url);
          const refererHost: string = this.extractHost(refererHdr);
          if (urlHost.length > 0 && refererHost.length > 0) {
            secFetchSiteHdr = (urlHost === refererHost) ? 'same-origin' : 'cross-site';
          }
        }

        const headerObj: HttpHeadersObject = {
          'User-Agent': ua,
          'Origin': originHdr.length > 0 ? originHdr : (refererHdr.length > 0 ? refererHdr : undefined),
          'Accept': acceptHdr,
          'Referer': refererHdr.length > 0 ? refererHdr : undefined,
          'Cookie': cookieHdr.length > 0 ? cookieHdr : undefined,
          'Authorization': authorizationHdr.length > 0 ? authorizationHdr : undefined,
          'Accept-Language': acceptLanguageHdr.length > 0 ? acceptLanguageHdr : undefined,
          'Cache-Control': cacheControlHdr.length > 0 ? cacheControlHdr : undefined,
          'Pragma': pragmaHdr.length > 0 ? pragmaHdr : undefined,
          'Sec-Fetch-Dest': secFetchDestHdr.length > 0 ? secFetchDestHdr : undefined,
          'Sec-Fetch-Mode': secFetchModeHdr.length > 0 ? secFetchModeHdr : undefined,
          'Sec-Fetch-Site': secFetchSiteHdr.length > 0 ? secFetchSiteHdr : undefined
        };

        const reqHeaderKeys: string[] = Object.keys(headerObj as Record<string, Object>);
        const uaLog: string = ua.substring(0, Math.min(128, ua.length));
        const refererLen: number = refererHdr.length;
        const originLen: number = originHdr.length > 0 ? originHdr.length : (refererHdr.length > 0 ? refererHdr.length : 0);
        const cookieLen: number = cookieHdr.length;
        logger.debug(TAG, `HTTP请求准备: url=${url}, timeout=${this.config.network.timeout}, headers=${reqHeaderKeys.length}, ua=${uaLog}, refererLen=${refererLen}, originLen=${originLen}, cookieLen=${cookieLen}, secSite=${secFetchSiteHdr}`);

        const requestOptions: http.HttpRequestOptions = {
          method: http.RequestMethod.GET,
          connectTimeout: this.config.network.timeout,
          readTimeout: this.config.network.timeout,
          header: headerObj as Object,
          expectDataType: http.HttpDataType.ARRAY_BUFFER
        };
        
        // 发送请求
        const response = await httpRequest.request(url, requestOptions);
        
        if (response.responseCode === 200 && response.result) {
          const duration: number = Date.now() - startTs;
          const respHeaderObj: Object = response.header as Object;
          const respHeaderKeys: string[] = Object.keys(respHeaderObj as Record<string, Object>);
          
          // 检查result类型
          const resultType = typeof response.result;
          logger.debug(TAG, `HTTP响应result类型: ${resultType}, constructor: ${response.result.constructor?.name || 'unknown'}`);
          
          // 直接使用response.result作为ArrayBuffer
          const imageBuffer = response.result as ArrayBuffer;
          
          // 检查byteLength是否存在
          if (!imageBuffer || typeof imageBuffer.byteLength === 'undefined') {
            logger.error(TAG, `imageBuffer无效: buffer=${imageBuffer}, byteLength=${imageBuffer?.byteLength}`);
            throw new Error('Invalid ArrayBuffer: byteLength is undefined');
          }
          
          const bytesLen: number = imageBuffer.byteLength;
          logger.info(TAG, `HTTP响应成功: code=${response.responseCode}, bytes=${bytesLen}, headers=${respHeaderKeys.length}, duration=${duration}`);
          
          // 创建图片源
          const imageSource = image.createImageSource(imageBuffer);
          
          // 创建PixelMap
          const decodingOptions: image.DecodingOptions = {
            desiredSize: options?.width && options?.height ? 
              { width: options.width, height: options.height } : undefined,
            desiredPixelFormat: image.PixelMapFormat.RGBA_8888
          };
          
          const pixelMap = await imageSource.createPixelMap(decodingOptions);
          
          // 清理HTTP请求
          httpRequest.destroy();
          
          return pixelMap;
        } else {
          const durationFail: number = Date.now() - startTs;
          logger.warn(TAG, `HTTP响应失败: code=${response.responseCode}, duration=${durationFail}`);
          throw new Error(`HTTP请求失败: ${response.responseCode}`);
        }
        
      } catch (error) {
        retryCount++;
        const errMsg: string = error instanceof Error ? error.message : String(error);
        logger.warn(TAG, `网络加载失败 (${retryCount}/${maxRetries + 1}): url=${url}, msg=${errMsg}`);
        
        if (retryCount <= maxRetries) {
          // 等待重试延迟
          await new Promise<void>(resolve => setTimeout(resolve, this.config.network.retryDelay));
        } else {
          throw error as Error;
        }
      }
    }
    
    return null;
  }

  /**
   * 内存缓存淘汰
   */
  private evictMemoryCacheIfNeeded(newImageSize: number): void {
    const maxSize = this.config.memoryCache.maxSize;
    const maxCount = this.config.memoryCache.maxCount;
    
    // 检查大小限制
    while (this.memoryCacheSize + newImageSize > maxSize || this.memoryCache.size >= maxCount) {
      if (this.memoryCache.size === 0) break;
      
      let evictKey: string;
      
      if (this.config.memoryCache.evictionPolicy === 'LRU') {
        // LRU淘汰策略
        evictKey = this.findLRUKey();
      } else {
        // LFU淘汰策略
        evictKey = this.findLFUKey();
      }
      
      const evictEntry = this.memoryCache.get(evictKey);
      if (evictEntry) {
        this.memoryCache.delete(evictKey);
        this.memoryCacheSize -= evictEntry.size;
        
        // 释放PixelMap资源
        evictEntry.pixelMap.release();
        
        logger.debug(TAG, `内存缓存淘汰: ${evictKey}`);
      }
    }
  }

  /**
   * 磁盘缓存淘汰
   */
  private async evictDiskCacheIfNeeded(): Promise<void> {
    try {
      // 使用内存追踪的大小，避免每次都扫描目录
      if (this.diskCacheSize <= this.config.diskCache.maxSize) {
        return;
      }
      
      // 按最后访问时间排序
      const sortedEntries = Array.from(this.diskCacheIndex.values())
        .sort((a, b) => a.lastAccessTime - b.lastAccessTime);
      
      // 删除最旧的文件直到大小合适
      const targetSize = this.config.diskCache.maxSize * 0.8; // 清理到80%
      let removedSize = 0;
      
      for (const entry of sortedEntries) {
        if (this.diskCacheSize - removedSize <= targetSize) {
          break;
        }
        
        await this.removeFromDiskCache(entry.key);
        removedSize += entry.size;
      }
      
      logger.info(TAG, `磁盘缓存清理完成，清理大小: ${removedSize}`);
      
    } catch (error) {
      logger.error(TAG, '磁盘缓存淘汰失败' + String(error));
    }
  }

  /**
   * 查找LRU键
   */
  private findLRUKey(): string {
    let lruKey = '';
    let lruTime = Date.now();
    
    for (const mapEntry of this.memoryCache) {
      const key = mapEntry[0];
      const entry = mapEntry[1];
      if (entry.accessTime < lruTime) {
        lruTime = entry.accessTime;
        lruKey = key;
      }
    }
    
    return lruKey;
  }

  /**
   * 查找LFU键
   */
  private findLFUKey(): string {
    let lfuKey = '';
    let lfuCount = Number.MAX_SAFE_INTEGER;
    
    for (const mapEntry of this.memoryCache) {
      const key = mapEntry[0];
      const entry = mapEntry[1];
      if (entry.accessCount < lfuCount) {
        lfuCount = entry.accessCount;
        lfuKey = key;
      }
    }
    
    return lfuKey;
  }

  /**
   * 从磁盘缓存移除
   */
  private async removeFromDiskCache(cacheKey: string): Promise<void> {
    try {
      const cacheInfo = this.diskCacheIndex.get(cacheKey);
      if (cacheInfo) {
        if (await this.sandboxManager.exists(cacheInfo.filePath)) {
          await this.sandboxManager.deleteFile(cacheInfo.filePath);
        }
        this.diskCacheIndex.delete(cacheKey);
        this.diskCacheSize -= cacheInfo.size; // 更新磁盘缓存大小
        
        logger.debug(TAG, `从磁盘缓存移除: ${cacheKey}`);
      }
    } catch (error) {
      logger.error(TAG, '从磁盘缓存移除失败' + String(error));
    }
  }

  /**
   * 生成缓存键
   */
  private generateCacheKey(url: string, options?: LoadOptions): string {
    let base: string = url;
    if (options && options.width && options.height) {
      base = base + `_${options.width}x${options.height}`;
    }
    if (options && options.quality) {
      base = base + `_q${options.quality}`;
    }
    if (options && options.sourceId !== undefined) {
      base = base + `_s${String(options.sourceId)}`;
    }
    if (options && options.loadingMethod !== undefined) {
      base = base + `_m${String(options.loadingMethod)}`;
    }
    if (options && options.partitionKey && options.partitionKey.length > 0) {
      base = base + `_p${options.partitionKey}`;
    }
    if (options && options.headers && options.headers.referer) {
      base = base + `_r${this.simpleHash(String(options.headers.referer))}`;
    }
    if (options && options.headers && options.headers.cookie) {
      base = base + `_c${this.simpleHash(String(options.headers.cookie))}`;
    }
    return this.simpleHash(base);
  }

  /**
   * 简单哈希算法
   */
  private simpleHash(str: string): string {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // 转换为32位整数
    }
    return Math.abs(hash).toString(36);
  }

  /**
   * 计算PixelMap大小
   */
  private async calculatePixelMapSize(pixelMap: image.PixelMap): Promise<number> {
    const imageInfo = await pixelMap.getImageInfo();
    return imageInfo.size.width * imageInfo.size.height * 4; // RGBA_8888
  }

  /**
   * 初始化磁盘缓存索引
   */
  private async initializeDiskCacheIndex(): Promise<void> {
    try {
      const coversDir = this.sandboxManager.getDirectory('covers');
      
      if (!await this.sandboxManager.exists(coversDir)) {
        return;
      }
      
      const files = await this.sandboxManager.listDirectory(coversDir);
      
      for (const file of files) {
        // 支持jpg、png、webp三种磁盘缓存文件格式
        if (file.endsWith('.jpg') || file.endsWith('.png') || file.endsWith('.webp')) {
          const filePath = `${coversDir}/${file}`;
          const fileInfo = await this.sandboxManager.getFileInfo(filePath);
          const cacheKey = file.substring(0, file.lastIndexOf('.'));
          
          const cacheInfo: DiskCacheInfo = {
            key: cacheKey,
            filePath: filePath,
            size: fileInfo.size,
            createTime: fileInfo.createTime,
            lastAccessTime: fileInfo.lastAccessTime
          };
          
          this.diskCacheIndex.set(cacheKey, cacheInfo);
        }
      }
      
      logger.info(TAG, `磁盘缓存索引初始化完成，缓存文件数: ${this.diskCacheIndex.size}`);
      
    } catch (error) {
      logger.error(TAG, '初始化磁盘缓存索引失败' + String(error));
    }
  }

  /**
   * 合并配置
   */
  private mergeConfig(defaultConfig: ImageCacheConfig, userConfig: Partial<ImageCacheConfig>): ImageCacheConfig {
    const mergedMemoryCache: MemoryCacheConfig = {
      maxSize: userConfig.memoryCache?.maxSize ?? defaultConfig.memoryCache.maxSize,
      maxCount: userConfig.memoryCache?.maxCount ?? defaultConfig.memoryCache.maxCount,
      evictionPolicy: userConfig.memoryCache?.evictionPolicy ?? defaultConfig.memoryCache.evictionPolicy
    };
    
    const mergedDiskCache: DiskCacheConfig = {
      maxSize: userConfig.diskCache?.maxSize ?? defaultConfig.diskCache.maxSize,
      maxAge: userConfig.diskCache?.maxAge ?? defaultConfig.diskCache.maxAge,
      compressionQuality: userConfig.diskCache?.compressionQuality ?? defaultConfig.diskCache.compressionQuality
    };
    
    const mergedNetwork: NetworkConfig = {
      timeout: userConfig.network?.timeout ?? defaultConfig.network.timeout,
      retryCount: userConfig.network?.retryCount ?? defaultConfig.network.retryCount,
      retryDelay: userConfig.network?.retryDelay ?? defaultConfig.network.retryDelay
    };
    
    return {
      memoryCache: mergedMemoryCache,
      diskCache: mergedDiskCache,
      network: mergedNetwork
    };
  }

  /**
   * 启动清理定时器
   */
  private startCleanupTimer(): void {
    // 每小时清理一次过期缓存
    setInterval(() => {
      this.cleanupExpiredCache();
    }, 60 * 60 * 1000);
  }

  /**
   * 清理过期缓存
   */
  private async cleanupExpiredCache(): Promise<void> {
    try {
      const now = Date.now();
      const expiredKeys: string[] = [];
      
      // 查找过期的磁盘缓存
      for (const mapEntry of this.diskCacheIndex) {
        const key = mapEntry[0];
        const cacheInfo = mapEntry[1];
        if (now - cacheInfo.createTime > this.config.diskCache.maxAge) {
          expiredKeys.push(key);
        }
      }
      
      // 删除过期缓存
      for (const key of expiredKeys) {
        await this.removeFromDiskCache(key);
      }
      
      if (expiredKeys.length > 0) {
        logger.info(TAG, `清理过期缓存: ${expiredKeys.length} 个文件`);
      }
      
    } catch (error) {
      logger.error(TAG, '清理过期缓存失败' + String(error));
    }
  }

  /**
   * 清空内存缓存
   */
  public clearMemoryCache(): void {
    try {
      // 释放所有PixelMap
      for (const entry of this.memoryCache.values()) {
        entry.pixelMap.release();
      }
      this.memoryCache.clear();
      this.memoryCacheSize = 0;
      logger.info(TAG, '内存缓存已清空');
    } catch (error) {
      logger.error(TAG, '清空内存缓存失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 清空所有缓存
   */
  public async clearAllCache(): Promise<void> {
    try {
      // 清空内存缓存
      this.clearMemoryCache();
      
      // 清空磁盘缓存
      const coversDir = this.sandboxManager.getDirectory('covers');
      const files = await this.sandboxManager.listDirectory(coversDir);
      
      for (const file of files) {
        const filePath = `${coversDir}/${file}`;
        // 检查是否为目录，跳过目录（如source_X）
        try {
          const stat = fs.statSync(filePath);
          if (stat.isDirectory()) {
            logger.debug(TAG, `跳过目录: ${file}`);
            continue;
          }
        } catch (e) {
          logger.warn(TAG, `获取文件信息失败: ${file}, ${e}`);
          continue;
        }
        await this.sandboxManager.deleteFile(filePath);
      }
      
      this.diskCacheIndex.clear();
      
      logger.info(TAG, '所有缓存已清空');
      
    } catch (error) {
      logger.error(TAG, '清空缓存失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 获取缓存统计信息
   */
  public async getCacheStats(): Promise<CacheStats> {
    try {
      const coversDir = this.sandboxManager.getDirectory('covers');
      const diskSize = await this.sandboxManager.getDirectorySize(coversDir);
      
      const memoryCacheStats: MemoryCacheStats = {
        size: this.memoryCacheSize,
        count: this.memoryCache.size,
        hitRate: 0 // 需要实现命中率统计
      };
      
      const diskCacheStats: DiskCacheStats = {
        size: diskSize,
        count: this.diskCacheIndex.size
      };
      
      const cacheStats: CacheStats = {
        memoryCache: memoryCacheStats,
        diskCache: diskCacheStats
      };
      
      return cacheStats;
    } catch (error) {
      logger.error(TAG, '获取缓存统计信息失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 预加载图片
   */
  public async preloadImages(urls: string[], options?: LoadOptions): Promise<void> {
    try {
      const loadPromises = urls.map(url => this.loadImage(url, options));
      await Promise.allSettled(loadPromises);
      
      logger.info(TAG, `预加载图片完成: ${urls.length} 张`);
    } catch (error) {
      logger.error(TAG, '预加载图片失败' + String(error));
    }
  }

  private extractHost(u: string): string {
    if (!u || u.length === 0) { return ''; }
    const schemeIdx: number = u.indexOf('://');
    if (schemeIdx < 0) { return ''; }
    const start: number = schemeIdx + 3;
    let end: number = u.indexOf('/', start);
    if (end < 0) { end = u.length; }
    let host: string = u.substring(start, end);
    if (host.startsWith('www.')) { host = host.substring(4); }
    return host;
  }

  /**
   * 优化：从内存缓存获取Cookie，避免每次都查询数据库
   * @param sourceId 图源ID
   * @returns Cookie字符串
   */
  private async getCachedCookie(sourceId: number): Promise<string> {
    const now = Date.now();
    const cached = this.cookieCache.get(sourceId);
    
    // 检查缓存是否有效（未过期）
    if (cached && (now - cached.timestamp) < this.COOKIE_CACHE_TTL) {
      logger.debug(TAG, `使用Cookie缓存: sourceId=${sourceId}`);
      return cached.cookie;
    }
    
    // 缓存未命中或已过期，从数据库获取
    try {
      const cookie = await CookieManager.getInstance().getCookieString(sourceId);
      
      // 更新缓存
      const cacheEntry: CookieCacheEntry = {
        cookie: cookie,
        timestamp: now
      };
      this.cookieCache.set(sourceId, cacheEntry);
      
      logger.debug(TAG, `Cookie已缓存: sourceId=${sourceId}, length=${cookie.length}`);
      return cookie;
    } catch (error) {
      logger.error(TAG, `获取Cookie失败: sourceId=${sourceId}, error=${String(error)}`);
      return '';
    }
  }

  /**
   * 清除Cookie缓存（当Cookie更新时调用）
   * @param sourceId 可选，指定图源ID，不指定则清除所有
   */
  public clearCookieCache(sourceId?: number): void {
    if (sourceId !== undefined) {
      this.cookieCache.delete(sourceId);
      logger.debug(TAG, `清除Cookie缓存: sourceId=${sourceId}`);
    } else {
      this.cookieCache.clear();
      logger.debug(TAG, '清除所有Cookie缓存');
    }
  }

  /**
   * 预加载图片（仅下载到缓存，不返回PixelMap）
   * 用于后台预加载，减少首次显示时的加载时间
   */
  public async preloadImage(url: string, options?: LoadOptions): Promise<void> {
    try {
      logger.debug(TAG, `开始预加载图片: ${url.substring(0, 80)}`);
      
      // 使用OnlineImageLoader下载图片到缓存
      const onlineLoader = OnlineImageLoader.getInstance();
      
      // 构建请求头
      let onlineHeaders: OnlineRequestHeaders | undefined = undefined;
      if (options?.headers) {
        const headers: OnlineRequestHeaders = {
          userAgent: options.headers.userAgent || '',
          referer: options.headers.referer || '',
          cookie: options.headers.cookie || '',
          accept: options.headers.accept || 'image/webp,image/apng,image/*,*/*;q=0.8',
          acceptLanguage: options.headers.acceptLanguage || 'zh-CN,zh;q=0.9,en;q=0.8'
        };
        onlineHeaders = headers;
      }
      
      const loadOptions: OnlineLoadOptions = {
        headers: onlineHeaders,
        priority: 0  // 低优先级，不影响正常加载
      };
      
      // 下载图片（会自动缓存）
      await onlineLoader.load(url, loadOptions);
      logger.debug(TAG, `预加载完成: ${url.substring(0, 80)}`);
    } catch (error) {
      logger.warn(TAG, `预加载失败: ${url.substring(0, 80)}, ${error}`);
      // 预加载失败不抛出异常，不影响主流程
    }
  }

}
