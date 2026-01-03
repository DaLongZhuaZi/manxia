// 文件路径: src/main/ets/Framework/Cache/CacheConfigManager.ets
/**
 * 缓存配置管理器
 * 提供可调整的缓存参数配置
 * 支持运行时动态调整和持久化存储
 */

import { logger } from '../../Utils/Logger';
import { preferences } from '@kit.ArkData';
import { ValidationResult } from '../Utils/DataValidator';

const TAG = 'CacheConfigManager';

/**
 * 内存缓存配置接口
 */
export interface MemoryCacheConfig {
  maxCount: number;
  maxSize: number;
  enabled: boolean;
}

/**
 * 磁盘缓存配置接口
 */
export interface DiskCacheConfig {
  maxSize: number;
  maxAge: number;
  enabled: boolean;
  compressionQuality: number;
}

/**
 * 预加载配置接口
 */
export interface PreloadConfig {
  enabled: boolean;
  rangeNormal: number;
  rangeWebtoon: number;
  maxConcurrent: number;
}

/**
 * 网络配置接口
 */
export interface NetworkConfig {
  maxConcurrent: number;
  timeout: number;
  retryCount: number;
}

/**
 * 缓存配置接口
 */
export interface CacheConfig {
  memoryCache: MemoryCacheConfig;
  diskCache: DiskCacheConfig;
  preload: PreloadConfig;
  network: NetworkConfig;
}

/**
 * 默认配置
 */
function createDefaultConfig(): CacheConfig {
  const memoryCache: MemoryCacheConfig = {
    maxCount: 50,
    maxSize: 50 * 1024 * 1024,
    enabled: true
  };
  const diskCache: DiskCacheConfig = {
    maxSize: 500 * 1024 * 1024,
    maxAge: 7 * 24 * 60 * 60 * 1000,
    enabled: true,
    compressionQuality: 85
  };
  const preload: PreloadConfig = {
    enabled: true,
    rangeNormal: 2,
    rangeWebtoon: 3,
    maxConcurrent: 3
  };
  const network: NetworkConfig = {
    maxConcurrent: 10,
    timeout: 30000,
    retryCount: 2
  };
  const config: CacheConfig = {
    memoryCache: memoryCache,
    diskCache: diskCache,
    preload: preload,
    network: network
  };
  return config;
}

const DEFAULT_CONFIG: CacheConfig = createDefaultConfig();

/**
 * 缓存配置管理器
 */
export class CacheConfigManager {
  private static instance: CacheConfigManager | null = null;
  private config: CacheConfig = this.cloneConfig(DEFAULT_CONFIG);
  private preferences: preferences.Preferences | null = null;
  private readonly PREF_NAME = 'cache_config';
  private initialized: boolean = false;
  
  // 配置变更监听器
  private listeners: Array<(config: CacheConfig) => void> = [];

  private constructor() {
    logger.info(TAG, '缓存配置管理器初始化');
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): CacheConfigManager {
    if (!CacheConfigManager.instance) {
      CacheConfigManager.instance = new CacheConfigManager();
    }
    return CacheConfigManager.instance;
  }

  /**
   * 初始化配置
   */
  public async initialize(context: Context): Promise<void> {
    if (this.initialized) {
      return;
    }
    
    try {
      // 获取preferences实例
      this.preferences = await preferences.getPreferences(context, this.PREF_NAME);
      
      // 加载配置
      await this.loadConfig();
      
      this.initialized = true;
      logger.info(TAG, '缓存配置加载完成');
    } catch (error) {
      logger.error(TAG, `初始化失败: ${String(error)}`);
      // 使用默认配置
      this.config = this.cloneConfig(DEFAULT_CONFIG);
    }
  }

  /**
   * 加载配置
   */
  private async loadConfig(): Promise<void> {
    if (!this.preferences) {
      return;
    }
    
    try {
      const configStr = await this.preferences.get('config', '');
      if (configStr) {
        const savedConfig = JSON.parse(configStr as string) as CacheConfig;
        this.config = this.mergeConfig(this.cloneConfig(DEFAULT_CONFIG), savedConfig);
        logger.debug(TAG, '从存储加载配置');
      } else {
        this.config = this.cloneConfig(DEFAULT_CONFIG);
        await this.saveConfig();
        logger.debug(TAG, '使用默认配置');
      }
    } catch (error) {
      logger.error(TAG, `加载配置失败: ${String(error)}`);
      this.config = this.cloneConfig(DEFAULT_CONFIG);
    }
  }

  /**
   * 保存配置
   */
  private async saveConfig(): Promise<void> {
    if (!this.preferences) {
      return;
    }
    
    try {
      const configStr = JSON.stringify(this.config);
      await this.preferences.put('config', configStr);
      await this.preferences.flush();
      logger.debug(TAG, '配置已保存');
    } catch (error) {
      logger.error(TAG, `保存配置失败: ${String(error)}`);
    }
  }

  /**
   * 合并配置（保留默认值）
   */
  private mergeConfig(defaultConfig: CacheConfig, savedConfig: CacheConfig): CacheConfig {
    const result: CacheConfig = this.cloneConfig(defaultConfig);
    if (savedConfig.memoryCache) {
      result.memoryCache = this.mergeMemoryCache(result.memoryCache, savedConfig.memoryCache);
    }
    if (savedConfig.diskCache) {
      result.diskCache = this.mergeDiskCache(result.diskCache, savedConfig.diskCache);
    }
    if (savedConfig.preload) {
      result.preload = this.mergePreload(result.preload, savedConfig.preload);
    }
    if (savedConfig.network) {
      result.network = this.mergeNetwork(result.network, savedConfig.network);
    }
    return result;
  }

  private cloneConfig(config: CacheConfig): CacheConfig {
    const memoryCache: MemoryCacheConfig = {
      maxCount: config.memoryCache.maxCount,
      maxSize: config.memoryCache.maxSize,
      enabled: config.memoryCache.enabled
    };
    const diskCache: DiskCacheConfig = {
      maxSize: config.diskCache.maxSize,
      maxAge: config.diskCache.maxAge,
      enabled: config.diskCache.enabled,
      compressionQuality: config.diskCache.compressionQuality
    };
    const preload: PreloadConfig = {
      enabled: config.preload.enabled,
      rangeNormal: config.preload.rangeNormal,
      rangeWebtoon: config.preload.rangeWebtoon,
      maxConcurrent: config.preload.maxConcurrent
    };
    const network: NetworkConfig = {
      maxConcurrent: config.network.maxConcurrent,
      timeout: config.network.timeout,
      retryCount: config.network.retryCount
    };
    const result: CacheConfig = {
      memoryCache: memoryCache,
      diskCache: diskCache,
      preload: preload,
      network: network
    };
    return result;
  }

  private mergeMemoryCache(target: MemoryCacheConfig, source: MemoryCacheConfig): MemoryCacheConfig {
    const result: MemoryCacheConfig = {
      maxCount: source.maxCount !== undefined ? source.maxCount : target.maxCount,
      maxSize: source.maxSize !== undefined ? source.maxSize : target.maxSize,
      enabled: source.enabled !== undefined ? source.enabled : target.enabled
    };
    return result;
  }

  private mergeDiskCache(target: DiskCacheConfig, source: DiskCacheConfig): DiskCacheConfig {
    const result: DiskCacheConfig = {
      maxSize: source.maxSize !== undefined ? source.maxSize : target.maxSize,
      maxAge: source.maxAge !== undefined ? source.maxAge : target.maxAge,
      enabled: source.enabled !== undefined ? source.enabled : target.enabled,
      compressionQuality: source.compressionQuality !== undefined ? source.compressionQuality : target.compressionQuality
    };
    return result;
  }

  private mergePreload(target: PreloadConfig, source: PreloadConfig): PreloadConfig {
    const result: PreloadConfig = {
      enabled: source.enabled !== undefined ? source.enabled : target.enabled,
      rangeNormal: source.rangeNormal !== undefined ? source.rangeNormal : target.rangeNormal,
      rangeWebtoon: source.rangeWebtoon !== undefined ? source.rangeWebtoon : target.rangeWebtoon,
      maxConcurrent: source.maxConcurrent !== undefined ? source.maxConcurrent : target.maxConcurrent
    };
    return result;
  }

  private mergeNetwork(target: NetworkConfig, source: NetworkConfig): NetworkConfig {
    const result: NetworkConfig = {
      maxConcurrent: source.maxConcurrent !== undefined ? source.maxConcurrent : target.maxConcurrent,
      timeout: source.timeout !== undefined ? source.timeout : target.timeout,
      retryCount: source.retryCount !== undefined ? source.retryCount : target.retryCount
    };
    return result;
  }

  /**
   * 获取当前配置
   */
  public getConfig(): CacheConfig {
    return this.cloneConfig(this.config);
  }

  /**
   * 更新配置
   */
  public async updateConfig(newConfig: CacheConfig): Promise<void> {
    try {
      // 合并配置
      this.config = this.mergeConfig(this.config, newConfig);
      
      // 保存到存储
      await this.saveConfig();
      
      // 通知监听器
      this.notifyListeners();
      
      logger.info(TAG, '配置已更新');
    } catch (error) {
      logger.error(TAG, `更新配置失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 重置为默认配置
   */
  public async resetToDefault(): Promise<void> {
    this.config = this.cloneConfig(DEFAULT_CONFIG);
    await this.saveConfig();
    this.notifyListeners();
    logger.info(TAG, '配置已重置为默认值');
  }

  /**
   * 添加配置变更监听器
   */
  public addListener(listener: (config: CacheConfig) => void): void {
    this.listeners.push(listener);
  }

  /**
   * 移除配置变更监听器
   */
  public removeListener(listener: (config: CacheConfig) => void): void {
    const index = this.listeners.indexOf(listener);
    if (index > -1) {
      this.listeners.splice(index, 1);
    }
  }

  /**
   * 通知所有监听器
   */
  private notifyListeners(): void {
    const config = this.getConfig();
    for (const listener of this.listeners) {
      try {
        listener(config);
      } catch (error) {
        logger.error(TAG, `监听器执行失败: ${String(error)}`);
      }
    }
  }

  /**
   * 获取内存缓存配置
   */
  public getMemoryCacheConfig(): MemoryCacheConfig {
    const result: MemoryCacheConfig = {
      maxCount: this.config.memoryCache.maxCount,
      maxSize: this.config.memoryCache.maxSize,
      enabled: this.config.memoryCache.enabled
    };
    return result;
  }

  /**
   * 获取磁盘缓存配置
   */
  public getDiskCacheConfig(): DiskCacheConfig {
    const result: DiskCacheConfig = {
      maxSize: this.config.diskCache.maxSize,
      maxAge: this.config.diskCache.maxAge,
      enabled: this.config.diskCache.enabled,
      compressionQuality: this.config.diskCache.compressionQuality
    };
    return result;
  }

  /**
   * 获取预加载配置
   */
  public getPreloadConfig(): PreloadConfig {
    const result: PreloadConfig = {
      enabled: this.config.preload.enabled,
      rangeNormal: this.config.preload.rangeNormal,
      rangeWebtoon: this.config.preload.rangeWebtoon,
      maxConcurrent: this.config.preload.maxConcurrent
    };
    return result;
  }

  /**
   * 获取网络配置
   */
  public getNetworkConfig(): NetworkConfig {
    const result: NetworkConfig = {
      maxConcurrent: this.config.network.maxConcurrent,
      timeout: this.config.network.timeout,
      retryCount: this.config.network.retryCount
    };
    return result;
  }

  /**
   * 更新内存缓存配置
   */
  public async updateMemoryCacheConfig(config: MemoryCacheConfig): Promise<void> {
    const newConfig = this.cloneConfig(this.config);
    newConfig.memoryCache = this.mergeMemoryCache(this.config.memoryCache, config);
    await this.updateConfig(newConfig);
  }

  /**
   * 更新磁盘缓存配置
   */
  public async updateDiskCacheConfig(config: DiskCacheConfig): Promise<void> {
    const newConfig = this.cloneConfig(this.config);
    newConfig.diskCache = this.mergeDiskCache(this.config.diskCache, config);
    await this.updateConfig(newConfig);
  }

  /**
   * 更新预加载配置
   */
  public async updatePreloadConfig(config: PreloadConfig): Promise<void> {
    const newConfig = this.cloneConfig(this.config);
    newConfig.preload = this.mergePreload(this.config.preload, config);
    await this.updateConfig(newConfig);
  }

  /**
   * 更新网络配置
   */
  public async updateNetworkConfig(config: NetworkConfig): Promise<void> {
    const newConfig = this.cloneConfig(this.config);
    newConfig.network = this.mergeNetwork(this.config.network, config);
    await this.updateConfig(newConfig);
  }

  /**
   * 获取配置摘要（用于显示）
   */
  public getConfigSummary(): string {
    const config = this.config;
    return `内存缓存: ${config.memoryCache.maxCount}张/${(config.memoryCache.maxSize / 1024 / 1024).toFixed(0)}MB, ` +
           `磁盘缓存: ${(config.diskCache.maxSize / 1024 / 1024).toFixed(0)}MB/${(config.diskCache.maxAge / 1000 / 60 / 60 / 24).toFixed(0)}天, ` +
           `预加载: ${config.preload.rangeNormal}/${config.preload.rangeWebtoon}页`;
  }

  /**
   * 验证配置有效性
   */
  public validateConfig(config: CacheConfig): ValidationResult {
    const errors: string[] = [];
    
    if (config.memoryCache) {
      if (config.memoryCache.maxCount !== undefined && config.memoryCache.maxCount < 1) {
        errors.push('内存缓存数量必须大于0');
      }
      if (config.memoryCache.maxSize !== undefined && config.memoryCache.maxSize < 1024 * 1024) {
        errors.push('内存缓存大小必须大于1MB');
      }
    }
    
    if (config.diskCache) {
      if (config.diskCache.maxSize !== undefined && config.diskCache.maxSize < 10 * 1024 * 1024) {
        errors.push('磁盘缓存大小必须大于10MB');
      }
      if (config.diskCache.maxAge !== undefined && config.diskCache.maxAge < 60 * 60 * 1000) {
        errors.push('磁盘缓存时间必须大于1小时');
      }
      if (config.diskCache.compressionQuality !== undefined && 
          (config.diskCache.compressionQuality < 1 || config.diskCache.compressionQuality > 100)) {
        errors.push('压缩质量必须在1-100之间');
      }
    }
    
    if (config.preload) {
      if (config.preload.rangeNormal !== undefined && config.preload.rangeNormal < 0) {
        errors.push('预加载范围不能为负数');
      }
      if (config.preload.maxConcurrent !== undefined && config.preload.maxConcurrent < 1) {
        errors.push('最大并发数必须大于0');
      }
    }
    
    if (config.network) {
      if (config.network.maxConcurrent !== undefined && config.network.maxConcurrent < 1) {
        errors.push('网络最大并发数必须大于0');
      }
      if (config.network.timeout !== undefined && config.network.timeout < 1000) {
        errors.push('超时时间必须大于1秒');
      }
    }
    
    const result: ValidationResult = {
      isValid: errors.length === 0,
      errors: errors
    };
    return result;
  }
}
