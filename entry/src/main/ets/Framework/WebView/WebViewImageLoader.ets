/**
 * WebView图片加载器核心实现
 * 整合图片拦截、缓存、源管理等功能
 * 符合HarmonyOS API 19和ArkTS规范
 */

import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  ComicSourceDatabaseRecord,
  PageInfoDatabaseRecord,
  ChapterInfoDatabaseRecord
} from 'manxia_core/src/main/ets/Framework/Database/DatabaseTypes';

const TAG = 'WebViewImageLoader';

// ==================== 基础类型定义 ====================

/**
 * 缓存项存储接口
 */
export interface CacheItemStorage {
  /** 获取缓存项 */
  get(key: string): CacheItem | undefined;
  /** 设置缓存项 */
  set(key: string, value: CacheItem): void;
  /** 移除缓存项 */
  remove(key: string): void;
  /** 检查是否存在 */
  has(key: string): boolean;
  /** 获取所有键 */
  keys(): string[];
  /** 获取所有值 */
  values(): CacheItem[];
  /** 清空缓存 */
  clear(): void;
}

/**
 * 图片请求信息接口
 */
export interface ImageRequestInfo {
  /** 请求URL */
  readonly url: string;
  /** 章节ID */
  readonly chapterId: string;
  /** 页面索引 */
  readonly pageIndex: number;
  /** 请求头 */
  readonly headers: Record<string, string>;
  /** 超时时间 */
  readonly timeout: number;
  /** 重试次数 */
  readonly retryCount: number;
  /** 创建时间 */
  readonly createTime: number;
}

/**
 * WebView加载结果接口
 */
export interface WebViewLoadingResult {
  /** 是否成功 */
  readonly success: boolean;
  /** 响应数据 */
  readonly data: ArrayBuffer | null;
  /** 错误信息 */
  readonly error: string | null;
  /** 响应头 */
  readonly headers: Record<string, string>;
  /** 状态码 */
  readonly statusCode: number;
  /** 加载耗时 */
  readonly loadTime: number;
}

/**
 * WebView加载状态枚举
 */
export enum WebViewLoadingState {
  /** 空闲 */
  IDLE = 'idle',
  /** 加载中 */
  LOADING = 'loading',
  /** 成功 */
  SUCCESS = 'success',
  /** 失败 */
  ERROR = 'error',
  /** 已取消 */
  CANCELLED = 'cancelled'
}

/**
 * WebView源配置接口
 */
export interface WebViewSourceConfig {
  /** 源ID */
  readonly sourceId: string;
  /** 用户代理 */
  readonly userAgent: string;
  /** 启用JavaScript */
  readonly enableJavaScript: boolean;
  /** 启用图片 */
  readonly enableImages: boolean;
  /** Cookie策略 */
  readonly cookiePolicy: string;
  /** 超时时间 */
  readonly timeout: number;
}

/**
 * 缓存项接口
 */
export interface CacheItem {
  /** 缓存键 */
  readonly key: string;
  /** 缓存数据 */
  readonly data: ArrayBuffer;
  /** 创建时间 */
  readonly createTime: number;
  /** 过期时间 */
  readonly expireTime: number;
  /** 访问次数 */
  accessCount: number;
  /** 最后访问时间 */
  lastAccessTime: number;
  /** 访问时间 */
  accessTime: number;
}

/**
 * 缓存统计信息接口
 */
export interface CacheStats {
  /** 缓存项数量 */
  readonly itemCount: number;
  /** 总大小 */
  readonly totalSize: number;
  /** 最大大小 */
  readonly maxSize: number;
}

/**
 * WebView实例信息接口
 */
export interface WebViewInstanceInfo {
  /** 实例ID */
  readonly instanceId: string;
  /** WebView控制器 */
  readonly controller: webview.WebviewController;
  /** 创建时间 */
  readonly createTime: number;
  /** 最后使用时间 */
  lastUsedTime: number;
  /** 是否正在使用 */
  isInUse: boolean;
  /** 源ID */
  readonly sourceId: string;
}

/**
 * WebView配置更新接口
 */
export interface WebViewConfigUpdate {
  /** 用户代理 */
  userAgent?: string;
  /** 启用JavaScript */
  enableJavaScript?: boolean;
  /** 启用图片 */
  enableImages?: boolean;
  /** Cookie策略 */
  cookiePolicy?: string;
  /** 超时时间 */
  timeout?: number;
}

/**
 * 缓存存储接口（替代Map）
 */
export interface CacheStorage {
  /** 获取缓存项 */
  get(key: string): CacheItem | undefined;
  /** 设置缓存项 */
  set(key: string, value: CacheItem): void;
  /** 删除缓存项 */
  delete(key: string): boolean;
  /** 检查是否存在 */
  has(key: string): boolean;
  /** 获取所有键 */
  keys(): string[];
  /** 获取所有值 */
  values(): CacheItem[];
  /** 清空缓存 */
  clear(): void;
  /** 获取大小 */
  size(): number;
}

/**
 * 源配置存储接口（替代Map）
 */
export interface SourceConfigStorage {
  /** 获取配置 */
  get(key: string): WebViewSourceConfig | undefined;
  /** 设置配置 */
  set(key: string, value: WebViewSourceConfig): void;
  /** 删除配置 */
  delete(key: string): boolean;
  /** 检查是否存在 */
  has(key: string): boolean;
  /** 获取所有键 */
  keys(): string[];
  /** 获取所有值 */
  values(): WebViewSourceConfig[];
  /** 清空配置 */
  clear(): void;
  /** 获取大小 */
  size(): number;
}

/**
 * WebView实例存储接口（替代Map）
 */
export interface WebViewInstanceStorage {
  /** 获取实例 */
  get(key: string): WebViewInstanceInfo | undefined;
  /** 设置实例 */
  set(key: string, value: WebViewInstanceInfo): void;
  /** 删除实例 */
  delete(key: string): boolean;
  /** 检查是否存在 */
  has(key: string): boolean;
  /** 获取所有键 */
  keys(): string[];
  /** 获取所有值 */
  values(): WebViewInstanceInfo[];
  /** 清空实例 */
  clear(): void;
  /** 获取大小 */
  size(): number;
}

/**
 * 监听器存储接口（替代Set）
 */
export interface ListenerStorage {
  listeners: WebViewImageLoadListener[];
}

// ==================== 监听器接口 ====================

/**
 * WebView图片加载监听器接口
 */
export interface WebViewImageLoadListener {
  /**
   * 加载开始回调
   */
  onLoadStart(request: ImageRequestInfo): void;

  /**
   * 加载进度回调
   */
  onLoadProgress(request: ImageRequestInfo, progress: number): void;

  /**
   * 加载成功回调
   */
  onLoadSuccess(request: ImageRequestInfo, response: WebViewLoadingResult): void;

  /**
   * 加载失败回调
   */
  onLoadError(request: ImageRequestInfo, error: string): void;

  /**
   * 加载完成回调
   */
  onLoadComplete(request: ImageRequestInfo, result: WebViewLoadingResult): void;
}

// ==================== 核心接口 ====================

/**
 * WebView图片加载器接口
 */
export interface IWebViewImageLoader {
  /**
   * 初始化加载器
   */
  initialize(): void;

  /**
   * 加载图片
   */
  loadImage(request: ImageRequestInfo): WebViewLoadingResult;

  /**
   * 取消加载
   */
  cancelLoad(requestId: string): void;

  /**
   * 添加加载监听器
   */
  addLoadListener(listener: WebViewImageLoadListener): void;

  /**
   * 移除加载监听器
   */
  removeLoadListener(listener: WebViewImageLoadListener): void;

  /**
   * 清理资源
   */
  cleanup(): void;
}

/**
 * WebView源管理器接口
 */
export interface IWebViewSourceManager {
  /**
   * 初始化管理器
   */
  initialize(): void;

  /**
   * 初始化源配置
   */
  initializeSource(sourceRecord: ComicSourceDatabaseRecord): void;

  /**
   * 更新源配置
   */
  updateSourceConfig(sourceId: string, configUpdate: WebViewConfigUpdate): void;

  /**
   * 获取源配置
   */
  getSourceConfig(sourceId: string): WebViewSourceConfig | null;

  /**
   * 移除源配置
   */
  removeSource(sourceId: string): void;

  /**
   * 获取所有源ID
   */
  getAllSourceIds(): string[];

  /**
   * 获取WebView实例
   */
  getWebViewInstance(sourceId: string): webview.WebviewController | null;

  /**
   * 释放WebView实例
   */
  releaseWebViewInstance(sourceId: string): void;

  /**
   * 清理资源
   */
  cleanup(): void;
}

// ==================== 工具类 ====================

/**
 * 图片请求构建器类
 */
export class ImageRequestBuilder {
  private url: string = '';
  private chapterId: string = '';
  private pageIndex: number = 0;
  private headers: Record<string, string> = {};
  private timeout: number = 30000;
  private retryCount: number = 3;

  /**
   * 设置URL
   */
  setUrl(url: string): ImageRequestBuilder {
    this.url = url;
    return this;
  }

  /**
   * 设置章节ID
   */
  setChapterId(chapterId: string): ImageRequestBuilder {
    this.chapterId = chapterId;
    return this;
  }

  /**
   * 设置页面索引
   */
  setPageIndex(pageIndex: number): ImageRequestBuilder {
    this.pageIndex = pageIndex;
    return this;
  }

  /**
   * 设置请求头
   */
  setHeaders(headers: Record<string, string>): ImageRequestBuilder {
    this.headers = headers;
    return this;
  }

  /**
   * 设置超时时间
   */
  setTimeoutValue(timeout: number): ImageRequestBuilder {
    this.timeout = timeout;
    return this;
  }

  /**
   * 设置重试次数
   */
  setRetryCount(retryCount: number): ImageRequestBuilder {
    this.retryCount = retryCount;
    return this;
  }

  /**
   * 构建请求信息
   */
  build(): ImageRequestInfo {
    return {
      url: this.url,
      chapterId: this.chapterId,
      pageIndex: this.pageIndex,
      headers: this.headers,
      timeout: this.timeout,
      retryCount: this.retryCount,
      createTime: Date.now()
    };
  }
}

/**
 * WebView图片工具类
 */
export class WebViewImageUtils {
  /**
   * 生成缓存键
   */
  static generateCacheKey(url: string, headers?: Record<string, string>): string {
    let key = url;
    if (headers && Object.keys(headers).length > 0) {
      const headerStr = Object.keys(headers)
        .sort()
        .reduce((acc: string[], key: string) => {
          acc.push(`${key}:${headers[key]}`);
          return acc;
        }, [])
        .join('|');
      key += `#${headerStr}`;
    }
    return key;
  }

  /**
   * 验证URL格式
   */
  static isValidUrl(url: string): boolean {
    try {
      // 使用正则表达式验证URL格式，避免使用URL构造函数
      const urlPattern = /^https?:\/\/([\w\-]+(\.[\w\-]+)*)(:\d+)?(\/[^\s]*)?$/i;
      return urlPattern.test(url);
    } catch (error) {
      logger.error(TAG, `URL验证失败: ${error instanceof Error ? error.message : String(error)}`);
      return false;
    }
  }

  /**
   * 获取文件扩展名
   */
  static getFileExtension(url: string): string {
    try {
      // 使用字符串操作替代URL构造函数
      const questionMarkIndex: number = url.indexOf('?');
      const hashIndex: number = url.indexOf('#');
      
      // 找到路径部分的结束位置
      let pathEnd: number = url.length;
      if (questionMarkIndex !== -1) {
        pathEnd = Math.min(pathEnd, questionMarkIndex);
      }
      if (hashIndex !== -1) {
        pathEnd = Math.min(pathEnd, hashIndex);
      }
      
      const pathname: string = url.substring(0, pathEnd);
      const lastSlashIndex: number = pathname.lastIndexOf('/');
      const filename: string = lastSlashIndex !== -1 ? pathname.substring(lastSlashIndex + 1) : pathname;
      const lastDotIndex: number = filename.lastIndexOf('.');
      
      return lastDotIndex > 0 ? filename.substring(lastDotIndex + 1).toLowerCase() : '';
    } catch (error) {
      logger.error(TAG, `获取文件扩展名失败: ${error instanceof Error ? error.message : String(error)}`);
      return '';
    }
  }

  /**
   * 检查是否为图片URL
   */
  static isImageUrl(url: string): boolean {
    const extension = WebViewImageUtils.getFileExtension(url);
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'];
    return imageExtensions.includes(extension);
  }

  /**
   * 格式化文件大小
   */
  static formatFileSize(bytes: number): string {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }

  /**
   * 生成唯一ID
   */
  static generateUniqueId(): string {
    return `${Date.now()}_${Math.floor(Math.random() * 10000)}`;
  }
}

/**
 * WebView配置工厂类
 */
export class WebViewConfigFactory {
  /**
   * 从数据库记录创建配置
   */
  static createFromDatabaseRecord(record: ComicSourceDatabaseRecord): WebViewSourceConfig {
    return {
      sourceId: record.id,
      userAgent: record.userAgent || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      enableJavaScript: record.enableJavaScript === 1,
      enableImages: record.enableImages === 1,
      cookiePolicy: 'accept_all',
      timeout: record.timeout || 30000
    };
  }

  /**
   * 创建默认配置
   */
  static createDefault(sourceId: string): WebViewSourceConfig {
    return {
      sourceId: sourceId,
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      enableJavaScript: true,
      enableImages: true,
      cookiePolicy: 'accept_all',
      timeout: 30000
    };
  }
 }


/**
 * 缓存项存储实现类
 */
class CacheItemStorageImpl implements CacheItemStorage {
  private items: Map<string, CacheItem> = new Map<string, CacheItem>();

  get(key: string): CacheItem | undefined {
    return this.items.get(key);
  }

  set(key: string, value: CacheItem): void {
    this.items.set(key, value);
  }

  remove(key: string): void {
    this.items.delete(key);
  }

  has(key: string): boolean {
    return this.items.has(key);
  }

  keys(): string[] {
    return Array.from(this.items.keys());
  }

  values(): CacheItem[] {
    return Array.from(this.items.values());
  }

  clear(): void {
    this.items.clear();
  }
}

// ==================== 实现类 ====================

/**
 * WebView图片缓存实现类
 */
export class WebViewImageCache {
  private static instance: WebViewImageCache | null = null;
  private readonly cacheItems: CacheItemStorage = new CacheItemStorageImpl();
  private readonly maxCacheSize: number = 100 * 1024 * 1024; // 100MB
  private readonly maxCacheItems: number = 1000;
  private readonly defaultExpireTime: number = 24 * 60 * 60 * 1000; // 24小时
  private currentCacheSize: number = 0;
  private isInitialized: boolean = false;

  /**
   * 私有构造函数
   */
  private constructor() {}

  /**
   * 获取单例实例
   */
  static getInstance(): WebViewImageCache {
    if (!WebViewImageCache.instance) {
      WebViewImageCache.instance = new WebViewImageCache();
    }
    return WebViewImageCache.instance;
  }

  /**
   * 初始化缓存
   */
  initialize(): void {
    if (this.isInitialized) {
      return;
    }

    try {
      logger.info(TAG, '开始初始化WebView图片缓存');
      
      // 清理过期缓存
      this.cleanupExpiredItems();
      
      this.isInitialized = true;
      logger.info(TAG, 'WebView图片缓存初始化完成');
      
    } catch (error) {
      logger.error(TAG, `初始化WebView图片缓存失败: ${error instanceof Error ? error.message : String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 获取缓存项
   */
  get(key: string): ArrayBuffer | null {
    const item = this.cacheItems.get(key);
    if (!item) {
      return null;
    }

    // 检查是否过期
    if (Date.now() > item.expireTime) {
      this.remove(key);
      return null;
    }

    // 更新访问信息
    item.accessCount++;
    item.lastAccessTime = Date.now();

    return item.data;
  }

  /**
   * 设置缓存项
   */
  set(key: string, data: ArrayBuffer, expireTime?: number): void {
    try {
      const expire = expireTime || (Date.now() + this.defaultExpireTime);
      
      // 检查缓存大小限制
      if (data.byteLength > this.maxCacheSize / 10) {
        logger.warn(TAG, `缓存项过大，跳过缓存: ${key}, 大小: ${WebViewImageUtils.formatFileSize(data.byteLength)}`);
        return;
      }

      // 如果已存在，先移除旧的
      if (this.cacheItems.has(key)) {
        this.remove(key);
      }

      // 检查缓存容量
      this.ensureCacheCapacity(data.byteLength);

      // 添加新缓存项
      const item: CacheItem = {
        key: key,
        data: data,
        createTime: Date.now(),
        expireTime: expire,
        accessCount: 1,
        lastAccessTime: Date.now(),
        accessTime: 0
      };

      this.cacheItems.set(key, item);
      this.currentCacheSize += data.byteLength;

      logger.debug(TAG, `缓存项已添加: ${key}, 大小: ${WebViewImageUtils.formatFileSize(data.byteLength)}`);

    } catch (error) {
      logger.error(TAG, `设置缓存项失败: ${key}, 错误: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 移除缓存项
   */
  remove(key: string): void {
    const item = this.cacheItems.get(key);
    if (item) {
      this.currentCacheSize -= item.data.byteLength;
      this.cacheItems.remove(key);
      logger.debug(TAG, `缓存项已移除: ${key}`);
    }
  }

  /**
   * 清空缓存
   */
  clear(): void {
    this.cacheItems.clear();
    this.currentCacheSize = 0;
    logger.info(TAG, '缓存已清空');
  }

  /**
   * 获取缓存统计信息
   */
  getStats(): CacheStats {
    const stats: CacheStats = {
      itemCount: this.cacheItems.keys().length,
      totalSize: this.currentCacheSize,
      maxSize: this.maxCacheSize
    };
    return stats;
  }

  /**
   * 确保缓存容量
   */
  private ensureCacheCapacity(newItemSize: number): void {
    // 检查项目数量限制
    const currentItemCount = this.cacheItems.keys().length;
    if (currentItemCount >= this.maxCacheItems) {
      this.evictLeastRecentlyUsed(1);
    }

    // 检查大小限制
    while (this.currentCacheSize + newItemSize > this.maxCacheSize) {
      this.evictLeastRecentlyUsed(1);
    }
  }

  /**
   * 淘汰最少使用的缓存项
   */
  private evictLeastRecentlyUsed(count: number): void {
    const items: CacheItem[] = this.cacheItems.values();
    if (items.length === 0) {
      return;
    }

    // 按最后访问时间排序
    items.sort((a: CacheItem, b: CacheItem) => a.lastAccessTime - b.lastAccessTime);

    // 移除最少使用的项目
    for (let i = 0; i < Math.min(count, items.length); i++) {
      this.remove(items[i].key);
    }
  }

  /**
   * 清理过期项目
   */
  private cleanupExpiredItems(): void {
    const now = Date.now();
    const keys = this.cacheItems.keys();
    let removedCount = 0;

    keys.forEach(key => {
      const item = this.cacheItems.get(key);
      if (item && now > item.expireTime) {
        this.remove(key);
        removedCount++;
      }
    });

    if (removedCount > 0) {
      logger.info(TAG, `清理了${removedCount}个过期缓存项`);
    }
  }

  /**
   * 清理资源
   */
  cleanup(): void {
    logger.info(TAG, '清理WebView图片缓存资源');
    this.clear();
    this.isInitialized = false;
  }
}

/**
 * WebView图片拦截器实现类
 */
export class WebViewImageInterceptor {
  private static instance: WebViewImageInterceptor | null = null;
  private readonly loadListeners: WebViewImageLoadListener[] = [];
  private readonly imageCache: WebViewImageCache;
  private isInitialized: boolean = false;

  /**
   * 私有构造函数
   */
  private constructor() {
    this.imageCache = WebViewImageCache.getInstance();
  }

  /**
   * 获取单例实例
   */
  static getInstance(): WebViewImageInterceptor {
    if (!WebViewImageInterceptor.instance) {
      WebViewImageInterceptor.instance = new WebViewImageInterceptor();
    }
    return WebViewImageInterceptor.instance;
  }

  /**
   * 初始化拦截器
   */
  initialize(): void {
    if (this.isInitialized) {
      return;
    }

    try {
      logger.info(TAG, '开始初始化WebView图片拦截器');
      
      // 初始化图片缓存
      this.imageCache.initialize();
      
      this.isInitialized = true;
      logger.info(TAG, 'WebView图片拦截器初始化完成');
      
    } catch (error) {
      logger.error(TAG, `初始化WebView图片拦截器失败: ${error instanceof Error ? error.message : String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 添加加载监听器
   */
  addLoadListener(listener: WebViewImageLoadListener): void {
    if (this.loadListeners.indexOf(listener) === -1) {
      this.loadListeners.push(listener);
    }
  }

  /**
   * 移除加载监听器
   */
  removeLoadListener(listener: WebViewImageLoadListener): void {
    const index = this.loadListeners.indexOf(listener);
    if (index !== -1) {
      this.loadListeners.splice(index, 1);
    }
  }

  /**
   * 拦截图片请求
   */
  interceptImageRequest(request: ImageRequestInfo): WebViewLoadingResult {
    try {
      // 通知加载开始
      this.notifyLoadStart(request);

      // 检查缓存
      const cacheKey = WebViewImageUtils.generateCacheKey(request.url, request.headers);
      const cachedData = this.imageCache.get(cacheKey);
      
      if (cachedData) {
        logger.debug(TAG, `从缓存获取图片: ${request.url}`);
        
        const result: WebViewLoadingResult = {
          success: true,
          data: cachedData,
          error: null,
          headers: {},
          statusCode: 200,
          loadTime: 0
        };

        this.notifyLoadSuccess(request, result);
        this.notifyLoadComplete(request, result);
        return result;
      }

      // 模拟网络请求（实际实现需要通过WebView进行）
      const result = this.performNetworkRequest(request);
      
      // 缓存成功的结果
      if (result.success && result.data) {
        this.imageCache.set(cacheKey, result.data);
      }

      // 通知结果
      if (result.success) {
        this.notifyLoadSuccess(request, result);
      } else {
        this.notifyLoadError(request, result.error || '未知错误');
      }
      
      this.notifyLoadComplete(request, result);
      return result;

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `拦截图片请求失败: ${request.url}, 错误: ${errorMsg}`);
      
      const result: WebViewLoadingResult = {
        success: false,
        data: null,
        error: errorMsg,
        headers: {},
        statusCode: 0,
        loadTime: 0
      };

      this.notifyLoadError(request, errorMsg);
      this.notifyLoadComplete(request, result);
      return result;
    }
  }

  /**
   * 执行网络请求（模拟实现）
   */
  private performNetworkRequest(request: ImageRequestInfo): WebViewLoadingResult {
    // 这里应该通过WebView实际执行网络请求
    // 由于ArkTS限制，这里只是模拟实现
    logger.debug(TAG, `执行网络请求: ${request.url}`);
    
    // 直接返回模拟结果，避免使用Promise构造函数和setTimeout
    const result: WebViewLoadingResult = {
      success: false,
      data: null,
      error: '模拟实现，需要实际的WebView网络请求',
      headers: {},
      statusCode: 0,
      loadTime: 1000
    };
    
    return result;
  }

  /**
   * 通知加载开始
   */
  private notifyLoadStart(request: ImageRequestInfo): void {
    this.loadListeners.forEach(listener => {
      try {
        listener.onLoadStart(request);
      } catch (error) {
        logger.error(TAG, `通知加载开始失败: ${error instanceof Error ? error.message : String(error)}`);
      }
    });
  }

  /**
   * 通知加载进度
   */
  private notifyLoadProgress(request: ImageRequestInfo, progress: number): void {
    this.loadListeners.forEach(listener => {
      try {
        listener.onLoadProgress(request, progress);
      } catch (error) {
        logger.error(TAG, `通知加载进度失败: ${error instanceof Error ? error.message : String(error)}`);
      }
    });
  }

  /**
   * 通知加载成功
   */
  private notifyLoadSuccess(request: ImageRequestInfo, response: WebViewLoadingResult): void {
    this.loadListeners.forEach(listener => {
      try {
        listener.onLoadSuccess(request, response);
      } catch (error) {
        logger.error(TAG, `通知加载成功失败: ${error instanceof Error ? error.message : String(error)}`);
      }
    });
  }

  /**
   * 通知加载失败
   */
  private notifyLoadError(request: ImageRequestInfo, error: string): void {
    this.loadListeners.forEach(listener => {
      try {
        listener.onLoadError(request, error);
      } catch (error) {
        logger.error(TAG, `通知加载失败失败: ${error instanceof Error ? error.message : String(error)}`);
      }
    });
  }

  /**
   * 通知加载完成
   */
  private notifyLoadComplete(request: ImageRequestInfo, result: WebViewLoadingResult): void {
    this.loadListeners.forEach(listener => {
      try {
        listener.onLoadComplete(request, result);
      } catch (error) {
        logger.error(TAG, `通知加载完成失败: ${error instanceof Error ? error.message : String(error)}`);
      }
    });
  }

  /**
   * 清理资源
   */
  cleanup(): void {
    logger.info(TAG, '清理WebView图片拦截器资源');
    this.loadListeners.length = 0;
    this.imageCache.cleanup();
    this.isInitialized = false;
  }
}