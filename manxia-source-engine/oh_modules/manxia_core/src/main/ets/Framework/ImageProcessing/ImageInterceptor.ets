// 文件路径:entry/src/main/ets/Framework/ImageProcessing/ImageInterceptor.ets
/**
 * 图片请求拦截器
 * 负责拦截图片请求并应用解扰算法
 */

import { logger } from '../../Utils/Logger';
import { ImageDescramblerRegistry, AlgorithmConfig } from './ImageDescramblerRegistry';

const TAG = 'ImageInterceptor';

/**
 * 图源配置
 */
interface SourceConfig {
  sourceId: number;
  config: AlgorithmConfig;
}

/**
 * 图片拦截器
 */
export class ImageInterceptor {
  private static instance: ImageInterceptor | null = null;
  private registry: ImageDescramblerRegistry;
  private sourceConfigs: Map<number, AlgorithmConfig> = new Map();
  private cacheEnabled: boolean = true;
  private processedCache: Map<string, ArrayBuffer> = new Map();
  private readonly MAX_CACHE_SIZE = 50; // 最多缓存50张处理后的图片

  private constructor() {
    this.registry = ImageDescramblerRegistry.getInstance();
    logger.info(TAG, '图片拦截器已初始化');
  }

  /**
   * 获取单例实例
   */
  static getInstance(): ImageInterceptor {
    if (!ImageInterceptor.instance) {
      ImageInterceptor.instance = new ImageInterceptor();
    }
    return ImageInterceptor.instance;
  }

  /**
   * 注册图源配置
   */
  registerSource(sourceId: number, config: AlgorithmConfig): void {
    this.sourceConfigs.set(sourceId, config);
    logger.info(TAG, `注册图源配置: sourceId=${sourceId}, algorithm=${config.algorithm}`);
  }

  /**
   * 注销图源配置
   */
  unregisterSource(sourceId: number): void {
    this.sourceConfigs.delete(sourceId);
    logger.info(TAG, `注销图源配置: sourceId=${sourceId}`);
  }

  /**
   * 检查是否需要拦截
   */
  shouldIntercept(url: string, sourceId: number): boolean {
    const config = this.sourceConfigs.get(sourceId);
    if (!config || !config.enabled) {
      return false;
    }

    // 检查URL模式匹配
    if (config.urlPattern) {
      if (typeof config.urlPattern === 'string') {
        return url.includes(config.urlPattern);
      } else {
        return config.urlPattern.test(url);
      }
    }

    return true;
  }

  /**
   * 拦截并处理图片
   */
  async intercept(
    url: string,
    sourceId: number,
    imageData: ArrayBuffer
  ): Promise<ArrayBuffer> {
    try {
      // 检查是否需要拦截
      if (!this.shouldIntercept(url, sourceId)) {
        logger.debug(TAG, `图片无需处理: ${url}`);
        return imageData;
      }

      const config = this.sourceConfigs.get(sourceId);
      if (!config) {
        logger.warn(TAG, `未找到图源配置: sourceId=${sourceId}`);
        return imageData;
      }

      // 检查缓存
      if (this.cacheEnabled) {
        const cacheKey = this.getCacheKey(url, sourceId);
        const cached = this.processedCache.get(cacheKey);
        if (cached) {
          logger.debug(TAG, `使用缓存的处理结果: ${url}`);
          return cached;
        }
      }

      // 获取解扰算法
      const algorithm = this.registry.get(config.algorithm);
      if (!algorithm) {
        logger.error(TAG, `未找到解扰算法: ${config.algorithm}`);
        return imageData;
      }

      // 检查是否需要解扰
      if (algorithm.shouldDescramble && !algorithm.shouldDescramble(url, config.parameters)) {
        logger.debug(TAG, `图片无需解扰: ${url}`);
        return imageData;
      }

      // 执行解扰
      logger.info(TAG, `开始处理图片: ${url}`);
      const startTime = Date.now();
      const processedData = await algorithm.descramble(imageData, config.parameters);
      const elapsed = Date.now() - startTime;
      logger.info(TAG, `图片处理完成: ${url}, 耗时: ${elapsed}ms`);

      // 缓存结果
      if (this.cacheEnabled) {
        this.cacheProcessedImage(url, sourceId, processedData);
      }

      return processedData;
    } catch (error) {
      logger.error(TAG, `图片处理失败: ${url}`, String(error));
      // 失败时返回原始数据
      return imageData;
    }
  }

  /**
   * 生成缓存键
   */
  private getCacheKey(url: string, sourceId: number): string {
    return `${sourceId}:${url}`;
  }

  /**
   * 缓存处理后的图片
   */
  private cacheProcessedImage(url: string, sourceId: number, data: ArrayBuffer): void {
    const cacheKey = this.getCacheKey(url, sourceId);

    // 如果缓存已满，删除最旧的条目
    if (this.processedCache.size >= this.MAX_CACHE_SIZE) {
      const firstKey = this.processedCache.keys().next().value;
      this.processedCache.delete(firstKey);
      logger.debug(TAG, `缓存已满，删除最旧条目: ${firstKey}`);
    }

    this.processedCache.set(cacheKey, data);
    logger.debug(TAG, `缓存处理结果: ${cacheKey}`);
  }

  /**
   * 清除缓存
   */
  clearCache(sourceId?: number): void {
    if (sourceId !== undefined) {
      // 清除特定图源的缓存
      const keysToDelete: string[] = [];
      for (const key of this.processedCache.keys()) {
        if (key.startsWith(`${sourceId}:`)) {
          keysToDelete.push(key);
        }
      }
      for (const key of keysToDelete) {
        this.processedCache.delete(key);
      }
      logger.info(TAG, `清除图源缓存: sourceId=${sourceId}, 数量=${keysToDelete.length}`);
    } else {
      // 清除所有缓存
      const size = this.processedCache.size;
      this.processedCache.clear();
      logger.info(TAG, `清除所有缓存: 数量=${size}`);
    }
  }

  /**
   * 启用/禁用缓存
   */
  setCacheEnabled(enabled: boolean): void {
    this.cacheEnabled = enabled;
    logger.info(TAG, `缓存${enabled ? '已启用' : '已禁用'}`);
  }

  /**
   * 获取缓存统计
   */
  getCacheStats(): { size: number; maxSize: number } {
    return {
      size: this.processedCache.size,
      maxSize: this.MAX_CACHE_SIZE
    };
  }
}
