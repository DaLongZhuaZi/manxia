// 文件路径: entry/src/main/ets/Framework/Cache/LocalImageCacheManager.ets
// 职责: 专门管理本地漫画图片的PixelMap缓存，独立于在线图片缓存逻辑

import { image } from '@kit.ImageKit';
import fs from '@ohos.file.fs';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'LocalImageCacheManager';

/**
 * 缓存项信息
 */
interface CacheItem {
  pixelMap: image.PixelMap;
  size: number;  // 内存大小（字节）
  lastAccess: number;  // 最后访问时间
  width: number;
  height: number;
}

/**
 * 预加载任务
 */
interface PreloadTask {
  pageId: string;
  filePath: string;
  priority: number;
}

/**
 * 加载配置
 */
export interface LocalLoadConfig {
  maxWidth?: number;   // 最大宽度（用于降采样）
  maxHeight?: number;  // 最大高度（用于降采样）
  priority?: number;   // 加载优先级
  suppressFailureLog?: boolean; // 调用方会自行恢复时，失败日志降为警告
}

/**
 * 缓存统计信息
 */
export interface CacheStats {
  count: number;
  size: number;
  maxSize: number;
}

/**
 * 本地图片缓存管理器
 * 专门为本地漫画条漫模式优化，使用LRU策略管理PixelMap缓存
 */
export class LocalImageCacheManager {
  private static instance: LocalImageCacheManager | null = null;
  
  // LRU缓存：pageId -> CacheItem
  private cache: Map<string, CacheItem> = new Map();
  
  // 当前缓存总大小
  private currentCacheSize: number = 0;
  
  // 最大缓存大小（200MB，本地图片可以给更多空间，减少快速滑动时 LRU 淘汰频率）
  private readonly MAX_CACHE_SIZE: number = 200 * 1024 * 1024;
  
  // 最大缓存项数（80项，减少快速滑动时回滚重加载）
  private readonly MAX_CACHE_COUNT: number = 80;
  
  // 预加载队列
  private preloadQueue: PreloadTask[] = [];
  
  // 正在加载的任务
  private loadingTasks: Set<string> = new Set();
  
  // 最大并发加载数
  private readonly MAX_CONCURRENT_LOADS: number = 3;
  
  // 屏幕宽度（用于计算降采样）
  private screenWidth: number = 1080;
  
  // 加载完成回调
  private loadCompleteCallbacks: Map<string, ((pixelMap: image.PixelMap | null) => void)[]> = new Map();

  private constructor() {
    logger.info(TAG, '本地图片缓存管理器初始化');
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): LocalImageCacheManager {
    if (!LocalImageCacheManager.instance) {
      LocalImageCacheManager.instance = new LocalImageCacheManager();
    }
    return LocalImageCacheManager.instance;
  }

  /**
   * 设置屏幕宽度（用于计算降采样比例）
   */
  public setScreenWidth(width: number): void {
    if (width > 0) {
      this.screenWidth = width;
    }
  }

  /**
   * 从缓存获取PixelMap
   */
  public get(pageId: string): image.PixelMap | null {
    const item = this.cache.get(pageId);
    if (item) {
      // 更新访问时间（LRU）
      item.lastAccess = Date.now();
      return item.pixelMap;
    }
    return null;
  }

  /**
   * 检查是否在缓存中
   */
  public has(pageId: string): boolean {
    return this.cache.has(pageId);
  }

  /**
   * 检查是否正在加载
   */
  public isLoading(pageId: string): boolean {
    return this.loadingTasks.has(pageId);
  }

  /**
   * 异步加载本地图片到缓存
   * @param pageId 页面ID
   * @param filePath 文件路径
   * @param config 加载配置
   * @returns Promise<PixelMap | null>
   */
  public async loadImage(pageId: string, filePath: string, config?: LocalLoadConfig): Promise<image.PixelMap | null> {
    // 1. 检查缓存
    const cached = this.get(pageId);
    if (cached) {
      logger.debug(TAG, `缓存命中: ${pageId}`);
      return cached;
    }

    // 2. 检查是否正在加载
    if (this.loadingTasks.has(pageId)) {
      logger.debug(TAG, `等待加载中: ${pageId}`);
      return this.waitForLoad(pageId);
    }

    // 3. 开始加载
    return this.doLoadImage(pageId, filePath, config);
  }

  /**
   * 等待正在进行的加载完成
   */
  private waitForLoad(pageId: string): Promise<image.PixelMap | null> {
    return new Promise((resolve) => {
      const callbacks = this.loadCompleteCallbacks.get(pageId) || [];
      callbacks.push(resolve);
      this.loadCompleteCallbacks.set(pageId, callbacks);
    });
  }

  /**
   * 通知加载完成
   */
  private notifyLoadComplete(pageId: string, pixelMap: image.PixelMap | null): void {
    const callbacks = this.loadCompleteCallbacks.get(pageId);
    if (callbacks) {
      const callbacksSnapshot: Array<(pixelMap: image.PixelMap | null) => void> = callbacks.slice();
      callbacksSnapshot.forEach(cb => cb(pixelMap));
      this.loadCompleteCallbacks.delete(pageId);
    }
  }

  /**
   * 执行实际加载
   */
  private async doLoadImage(pageId: string, filePath: string, config?: LocalLoadConfig): Promise<image.PixelMap | null> {
    this.loadingTasks.add(pageId);
    let file: fs.File | null = null;
    let imageSource: image.ImageSource | null = null;
    
    try {
      // 处理文件路径
      let actualPath = filePath;
      if (filePath.startsWith('file://')) {
        actualPath = filePath.substring(7);
      }

      // 检查文件是否存在
      try {
        await fs.access(actualPath);
      } catch (e) {
        this.logLoadFailure(`文件不存在: ${actualPath}`, config);
        this.loadingTasks.delete(pageId);
        this.notifyLoadComplete(pageId, null);
        return null;
      }

      // 读取文件
      file = await fs.open(actualPath, fs.OpenMode.READ_ONLY);

      // 创建ImageSource
      imageSource = image.createImageSource(file.fd);
      if (!imageSource) {
        await fs.close(file);
        file = null;
        this.logLoadFailure(`创建ImageSource失败: ${pageId}`, config);
        this.loadingTasks.delete(pageId);
        this.notifyLoadComplete(pageId, null);
        return null;
      }

      // 获取图片信息
      const imageInfo = await imageSource.getImageInfo();
      const originalWidth = imageInfo.size.width;
      const originalHeight = imageInfo.size.height;

      // 计算降采样比例
      const sampleSize = this.calculateSampleSize(
        originalWidth, 
        originalHeight, 
        config?.maxWidth || this.screenWidth,
        config?.maxHeight || this.screenWidth * 3  // 条漫高度可以是宽度的3倍
      );

      // 解码选项
      const decodingOptions: image.DecodingOptions = {
        sampleSize: sampleSize,
        editable: false
      };

      // 解码为PixelMap
      const pixelMap = await imageSource.createPixelMap(decodingOptions);
      imageSource.release();
      imageSource = null;
      await fs.close(file);
      file = null;
      if (!pixelMap) {
        this.logLoadFailure(`创建PixelMap失败: ${pageId}`, config);
        this.loadingTasks.delete(pageId);
        this.notifyLoadComplete(pageId, null);
        return null;
      }

      // 获取实际尺寸
      const pmInfo = await pixelMap.getImageInfo();
      const width = pmInfo.size.width;
      const height = pmInfo.size.height;
      
      // 估算内存大小（RGBA每像素4字节）
      const memorySize = width * height * 4;

      // 添加到缓存前先清理空间
      await this.ensureCacheSpace(memorySize);

      // 添加到缓存
      const cacheItem: CacheItem = {
        pixelMap: pixelMap,
        size: memorySize,
        lastAccess: Date.now(),
        width: width,
        height: height
      };
      this.cache.set(pageId, cacheItem);
      this.currentCacheSize += memorySize;

      logger.info(TAG, `图片加载成功: ${pageId}, 尺寸=${width}x${height}, 采样=${sampleSize}, 内存=${(memorySize/1024/1024).toFixed(2)}MB`);
      
      this.loadingTasks.delete(pageId);
      this.notifyLoadComplete(pageId, pixelMap);
      
      // 处理预加载队列
      this.processPreloadQueue();
      
      return pixelMap;
    } catch (error) {
      try {
        if (imageSource !== null) {
          imageSource.release();
          imageSource = null;
        }
      } catch (_releaseError) {
      }
      try {
        if (file !== null) {
          await fs.close(file);
          file = null;
        }
      } catch (_closeError) {
      }
      this.logLoadFailure(`加载图片失败: ${pageId}, error=${String(error)}`, config);
      this.loadingTasks.delete(pageId);
      this.notifyLoadComplete(pageId, null);
      return null;
    }
  }

  private logLoadFailure(message: string, config?: LocalLoadConfig): void {
    if (config?.suppressFailureLog === true) {
      logger.warn(TAG, message);
      return;
    }
    logger.error(TAG, message);
  }

  /**
   * 计算降采样比例
   */
  private calculateSampleSize(originalWidth: number, originalHeight: number, maxWidth: number, maxHeight: number): number {
    let sampleSize = 1;
    
    if (originalWidth > maxWidth || originalHeight > maxHeight) {
      const widthRatio = Math.ceil(originalWidth / maxWidth);
      const heightRatio = Math.ceil(originalHeight / maxHeight);
      sampleSize = Math.min(widthRatio, heightRatio);
    }
    
    // sampleSize必须是2的幂次（某些平台限制）
    // 取最接近的2的幂次
    if (sampleSize > 1) {
      let powerOf2 = 1;
      while (powerOf2 * 2 <= sampleSize) {
        powerOf2 *= 2;
      }
      sampleSize = powerOf2;
    }
    
    return Math.max(1, sampleSize);
  }

  /**
   * 确保缓存有足够空间
   */
  private async ensureCacheSpace(requiredSize: number): Promise<void> {
    // 如果缓存项数超过最大值，清理最旧的
    while (this.cache.size >= this.MAX_CACHE_COUNT) {
      this.evictOldest();
    }

    // 如果内存超过最大值，清理最旧的
    while (this.currentCacheSize + requiredSize > this.MAX_CACHE_SIZE && this.cache.size > 0) {
      this.evictOldest();
    }
  }

  /**
   * 清除最旧的缓存项（LRU）
   */
  private evictOldest(): void {
    let oldestKey: string | null = null;
    let oldestTime = Infinity;

    this.cache.forEach((item, key) => {
      if (item.lastAccess < oldestTime) {
        oldestTime = item.lastAccess;
        oldestKey = key;
      }
    });

    if (oldestKey) {
      this.remove(oldestKey);
    }
  }

  /**
   * 从缓存移除指定项
   */
  public remove(pageId: string): void {
    const item = this.cache.get(pageId);
    if (item) {
      try {
        item.pixelMap.release();
      } catch (e) {
        logger.warn(TAG, `释放PixelMap失败: ${pageId}`);
      }
      this.currentCacheSize -= item.size;
      this.cache.delete(pageId);
      logger.debug(TAG, `移除缓存: ${pageId}`);
    }
  }

  /**
   * 批量预加载图片
   * @param tasks 预加载任务列表
   */
  public preload(tasks: Array<PreloadTask>): void {
    // 添加到预加载队列
    for (const task of tasks) {
      // 跳过已缓存或正在加载的
      if (this.cache.has(task.pageId) || this.loadingTasks.has(task.pageId)) {
        continue;
      }
      
      // 检查是否已在队列中
      const existingIndex = this.preloadQueue.findIndex(t => t.pageId === task.pageId);
      if (existingIndex >= 0) {
        // 更新优先级（取较高值）
        if (task.priority > this.preloadQueue[existingIndex].priority) {
          this.preloadQueue[existingIndex].priority = task.priority;
        }
      } else {
        this.preloadQueue.push(task);
      }
    }
    
    // 按优先级排序（高优先级在前）
    this.preloadQueue.sort((a, b) => b.priority - a.priority);
    
    // 开始处理队列
    this.processPreloadQueue();
  }

  /**
   * 处理预加载队列
   */
  private processPreloadQueue(): void {
    // 检查并发数
    while (this.loadingTasks.size < this.MAX_CONCURRENT_LOADS && this.preloadQueue.length > 0) {
      const task = this.preloadQueue.shift();
      if (task && !this.cache.has(task.pageId) && !this.loadingTasks.has(task.pageId)) {
        // 异步加载，不等待结果
        this.loadImage(task.pageId, task.filePath).catch((e: Error) => {
          logger.error(TAG, `预加载失败: ${task.pageId}, ${e.message}`);
        });
      }
    }
  }

  /**
   * 清理远离可见区域的缓存
   * @param visiblePageIds 当前可见的页面ID列表
   * @param allPageIds 所有页面ID列表（按顺序）
   * @param keepRange 保留范围（前后各保留多少页）
   */
  public cleanupDistant(visiblePageIds: string[], allPageIds: string[], keepRange: number = 15): void {
    if (visiblePageIds.length === 0 || allPageIds.length === 0) {
      return;
    }

    // 找出可见页面的索引范围
    let minVisibleIndex = Infinity;
    let maxVisibleIndex = -1;
    
    for (const visibleId of visiblePageIds) {
      const index = allPageIds.indexOf(visibleId);
      if (index >= 0) {
        minVisibleIndex = Math.min(minVisibleIndex, index);
        maxVisibleIndex = Math.max(maxVisibleIndex, index);
      }
    }

    if (minVisibleIndex === Infinity) {
      return;
    }

    // 计算保留范围
    const keepStart = Math.max(0, minVisibleIndex - keepRange);
    const keepEnd = Math.min(allPageIds.length - 1, maxVisibleIndex + keepRange);
    
    // 创建保留集合
    const keepSet = new Set<string>();
    for (let i = keepStart; i <= keepEnd; i++) {
      keepSet.add(allPageIds[i]);
    }

    // 清理不在保留范围内的缓存
    const toRemove: string[] = [];
    this.cache.forEach((_, pageId) => {
      if (!keepSet.has(pageId)) {
        toRemove.push(pageId);
      }
    });

    for (const pageId of toRemove) {
      this.remove(pageId);
    }

    if (toRemove.length > 0) {
      logger.info(TAG, `清理远离缓存: 移除${toRemove.length}项, 保留范围=[${keepStart}, ${keepEnd}]`);
    }
  }

  /**
   * 清空所有缓存
   */
  public clear(): void {
    this.cache.forEach((item, key) => {
      try {
        item.pixelMap.release();
      } catch (e) {
        // 忽略释放错误
      }
    });
    this.cache.clear();
    this.currentCacheSize = 0;
    this.preloadQueue = [];
    logger.info(TAG, '缓存已清空');
  }

  /**
   * 获取缓存统计信息
   */
  public getStats(): CacheStats {
    const stats: CacheStats = {
      count: this.cache.size,
      size: this.currentCacheSize,
      maxSize: this.MAX_CACHE_SIZE
    };
    return stats;
  }

  /**
   * 取消指定页面的预加载
   */
  public cancelPreload(pageId: string): void {
    const index = this.preloadQueue.findIndex(t => t.pageId === pageId);
    if (index >= 0) {
      this.preloadQueue.splice(index, 1);
    }
  }

  /**
   * 清空预加载队列
   */
  public clearPreloadQueue(): void {
    this.preloadQueue = [];
  }
}
