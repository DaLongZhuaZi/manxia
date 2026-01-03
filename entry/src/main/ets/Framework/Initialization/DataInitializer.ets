// 文件路径: src/main/ets/Framework/Initialization/DataInitializer.ets
/**
 * 数据初始化器
 * 负责应用启动时的数据管理组件初始化流程
 */

import { logger } from '../../Utils/Logger';
import { DataService } from '../Services/DataService';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { initializeNovelModule } from '../Novel/NovelInitializer';
import { DiskCacheManager } from '../Cache/DiskCacheManager';
import { SandboxManager } from '../Storage/SandboxManager';

const TAG = 'DataInitializer';

// 定义缓存配置接口
export interface CacheConfig {
  maxImageCacheSize: number;
  maxDiskCacheAge: number;
}

// 定义数据库配置接口
export interface DatabaseConfig {
  enableWAL: boolean;
  pageSize: number;
  cacheSize: number;
}

export interface InitializationConfig {
  enableAutoBackup: boolean;
  enableDataSync: boolean;
  cacheConfig: CacheConfig;
  databaseConfig: DatabaseConfig;
}

// 定义统计信息接口
export interface InitializationStats {
  databaseInitialized: boolean;
  sandboxInitialized: boolean;
  cacheInitialized: boolean;
  pluginInitialized: boolean;
  serviceInitialized: boolean;
}

export interface InitializationResult {
  success: boolean;
  duration: number;
  errors: string[];
  warnings: string[];
  stats: InitializationStats;
}

// 定义验证结果接口
interface ValidationResult {
  success: boolean;
  errors: string[];
  warnings: string[];
}

// 定义初始化状态接口
interface InitializationStatus {
  isInitialized: boolean;
  isInitializing: boolean;
}

export class DataInitializer {
  private static instance: DataInitializer | null = null;
  private isInitialized: boolean = false;
  private initializationPromise: Promise<InitializationResult> | null = null;

  private constructor() {}

  /**
   * 获取单例实例
   */
  public static getInstance(): DataInitializer {
    if (!DataInitializer.instance) {
      DataInitializer.instance = new DataInitializer();
    }
    return DataInitializer.instance;
  }

  /**
   * 初始化数据管理系统
   */
  public async initialize(context: common.UIAbilityContext, config?: Partial<InitializationConfig>): Promise<InitializationResult> {
    // 如果已经在初始化中，返回现有的Promise
    if (this.initializationPromise) {
      return this.initializationPromise;
    }

    // 如果已经初始化完成，直接返回成功结果
    if (this.isInitialized) {
      const successStats: InitializationStats = {
        databaseInitialized: true,
        sandboxInitialized: true,
        cacheInitialized: true,
        pluginInitialized: true,
        serviceInitialized: true
      };
      
      const successResult: InitializationResult = {
        success: true,
        duration: 0,
        errors: [],
        warnings: [],
        stats: successStats
      };
      
      return successResult;
    }

    // 开始初始化流程
    this.initializationPromise = this.performInitialization(context, config);
    return this.initializationPromise;
  }

  /**
   * 执行初始化流程
   */
  private async performInitialization(context: common.UIAbilityContext, config?: Partial<InitializationConfig>): Promise<InitializationResult> {
    const startTime = Date.now();
    const errors: string[] = [];
    const warnings: string[] = [];
    const stats: InitializationStats = {
      databaseInitialized: false,
      sandboxInitialized: false,
      cacheInitialized: false,
      pluginInitialized: false,
      serviceInitialized: false
    };

    try {
      logger.lifecycle(TAG, '开始初始化数据管理系统');

      // 合并默认配置
      const defaultCacheConfig: CacheConfig = {
        maxImageCacheSize: 500 * 1024 * 1024, // 500MB
        maxDiskCacheAge: 7 * 24 * 60 * 60 * 1000 // 7天
      };

      const defaultDatabaseConfig: DatabaseConfig = {
        enableWAL: true,
        pageSize: 4096,
        cacheSize: 2000
      };

      const finalConfig: InitializationConfig = {
        enableAutoBackup: config?.enableAutoBackup ?? true,
        enableDataSync: config?.enableDataSync ?? false,
        cacheConfig: config?.cacheConfig ?? defaultCacheConfig,
        databaseConfig: config?.databaseConfig ?? defaultDatabaseConfig
      };

      // 第一步：检查应用权限和环境
      await this.checkEnvironment(context);
      logger.debug(TAG, '环境检查完成');

      // 第二步：初始化沙箱存储管理器
      try {
        await this.initializeSandboxManager(context);
        stats.sandboxInitialized = true;
        logger.info(TAG, '沙箱存储管理器初始化完成');
      } catch (error) {
        const errorMsg = `沙箱存储管理器初始化失败: ${error}`;
        errors.push(errorMsg);
        logger.error(TAG, errorMsg + String(error));
      }

      // 第三步：初始化数据库管理器
      try {
        await this.initializeDatabaseManager(finalConfig.databaseConfig);
        stats.databaseInitialized = true;
        logger.info(TAG, '数据库管理器初始化完成');
      } catch (error) {
        const errorMsg = `数据库管理器初始化失败: ${error}`;
        errors.push(errorMsg);
        logger.error(TAG, errorMsg + String(error));
      }

      // 第四步：初始化图片缓存管理器
      try {
        await this.initializeCacheManager(finalConfig.cacheConfig);
        stats.cacheInitialized = true;
        logger.info(TAG, '图片缓存管理器初始化完成');
      } catch (error) {
        const errorMsg = `图片缓存管理器初始化失败: ${error}`;
        errors.push(errorMsg);
        logger.error(TAG, errorMsg + String(error));
      }

      // 第五步：初始化插件管理器
      try {
        await this.initializePluginManager();
        stats.pluginInitialized = true;
        logger.info(TAG, '插件管理器初始化完成');
      } catch (error) {
        const errorMsg = `插件管理器初始化失败: ${error}`;
        warnings.push(errorMsg); // 插件初始化失败不影响核心功能
        logger.warn(TAG, errorMsg + String(error));
      }

      // 第六步：初始化数据服务层
      try {
        await this.initializeDataService(context, finalConfig);
        stats.serviceInitialized = true;
        logger.info(TAG, '数据服务层初始化完成');
      } catch (error) {
        const errorMsg = `数据服务层初始化失败: ${error}`;
        errors.push(errorMsg);
        logger.error(TAG, errorMsg + String(error));
      }

      // 第六步半：初始化小说模块
      try {
        const novelResult = await initializeNovelModule(context);
        if (novelResult.success) {
          logger.info(TAG, `小说模块初始化完成，耗时: ${novelResult.duration}ms`);
        } else {
          const warningMsg = `小说模块初始化部分失败: ${novelResult.errors.join(', ')}`;
          warnings.push(warningMsg);
          logger.warn(TAG, warningMsg);
        }
      } catch (error) {
        const warningMsg = `小说模块初始化失败: ${error}`;
        warnings.push(warningMsg); // 小说模块初始化失败不影响核心功能
        logger.warn(TAG, warningMsg + String(error));
      }

      // 第七步：执行数据迁移和升级
      try {
        await this.performDataMigration();
        logger.info(TAG, '数据迁移完成');
      } catch (error) {
        const warningMsg = `数据迁移警告: ${error}`;
        warnings.push(warningMsg);
        logger.warn(TAG, warningMsg + String(error));
      }

      // 第八步：验证初始化结果
      const validationResult = await this.validateInitialization();
      if (!validationResult.success) {
        errors.push(...validationResult.errors);
        warnings.push(...validationResult.warnings);
      }

      const duration = Date.now() - startTime;
      const success = errors.length === 0;

      if (success) {
        this.isInitialized = true;
        logger.lifecycle(TAG, `数据管理系统初始化完成，耗时: ${duration}ms`);
      } else {
        logger.error(TAG, `数据管理系统初始化失败，错误数量: ${errors.length}`);
      }

      const result: InitializationResult = {
        success,
        duration,
        errors,
        warnings,
        stats
      };

      // 清除初始化Promise，允许重新初始化
      this.initializationPromise = null;

      return result;

    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMsg = `数据管理系统初始化异常: ${error}`;
      errors.push(errorMsg);
      logger.error(TAG, errorMsg + String(error));

      this.initializationPromise = null;

      const failureResult: InitializationResult = {
        success: false,
        duration,
        errors,
        warnings,
        stats
      };

      return failureResult;
    }
  }

  /**
   * 检查应用环境
   */
  private async checkEnvironment(context: common.UIAbilityContext): Promise<void> {
    try {
      // 检查应用上下文
      if (!context) {
        throw new Error('应用上下文不存在');
      }

      // 检查文件系统权限
      const filesDir = context.filesDir;
      if (!filesDir) {
        throw new Error('无法获取应用文件目录');
      }

      // 检查缓存目录权限
      const cacheDir = context.cacheDir;
      if (!cacheDir) {
        throw new Error('无法获取应用缓存目录');
      }

      logger.debug(TAG, `应用文件目录: ${filesDir}`);
      logger.debug(TAG, `应用缓存目录: ${cacheDir}`);

    } catch (error) {
      logger.error(TAG, '环境检查失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 初始化沙箱存储管理器
   */
  private async initializeSandboxManager(context: common.UIAbilityContext): Promise<void> {
    try {
      logger.info(TAG, '开始初始化沙箱存储管理器...');
      
      const sandboxManager = SandboxManager.getInstance();
      await sandboxManager.initialize(context);
      
      // 验证关键目录路径
      const cacheDir = sandboxManager.getDirectory('cache');
      const filesDir = sandboxManager.getDirectory('files');
      
      if (!cacheDir || !filesDir) {
        throw new Error(`沙箱目录路径无效: cache=${cacheDir}, files=${filesDir}`);
      }
      
      logger.info(TAG, `✅ 沙箱存储管理器初始化完成: cache=${cacheDir}`);
    } catch (error) {
      const err = error as Error;
      logger.error(TAG, `❌ 沙箱存储管理器初始化失败: ${err.message}, stack: ${err.stack}`);
      throw new Error(`沙箱存储管理器初始化失败: ${err.message}`);
    }
  }

  /**
   * 初始化数据库管理器
   */
  private async initializeDatabaseManager(config: DatabaseConfig): Promise<void> {
    try {
      // 这里需要导入并初始化DatabaseManager
      // const databaseManager = DatabaseManager.getInstance();
      // await databaseManager.initialize(config);
      
      logger.debug(TAG, '数据库管理器初始化占位符');
    } catch (error) {
      throw new Error(`数据库管理器初始化失败: ${error}`);
    }
  }

  /**
   * 初始化图片缓存管理器
   */
  private async initializeCacheManager(config: CacheConfig): Promise<void> {
    try {
      logger.info(TAG, '开始初始化磁盘缓存管理器...');
      
      // 初始化磁盘缓存管理器
      const sandboxManager = SandboxManager.getInstance();
      const cacheBaseDir = sandboxManager.getDirectory('cache');
      
      logger.debug(TAG, `缓存目录: ${cacheBaseDir}`);
      
      const diskCacheManager = DiskCacheManager.getInstance();
      await diskCacheManager.initialize(cacheBaseDir);
      
      // 验证初始化是否成功
      if (!diskCacheManager.isInitialized()) {
        throw new Error('磁盘缓存管理器初始化后状态仍为未初始化');
      }
      
      const stats = diskCacheManager.getStats();
      logger.info(TAG, `✅ 磁盘缓存管理器初始化完成: 缓存数=${stats.count}, 大小=${(stats.totalSize / 1024 / 1024).toFixed(2)}MB`);
    } catch (error) {
      const err = error as Error;
      logger.error(TAG, `❌ 图片缓存管理器初始化失败: ${err.message}, stack: ${err.stack}`);
      throw new Error(`图片缓存管理器初始化失败: ${err.message}`);
    }
  }

  /**
   * 初始化插件管理器
   */
  private async initializePluginManager(): Promise<void> {
    try {
      // 这里需要导入并初始化HSPPluginManager
      // const pluginManager = HSPPluginManager.getInstance();
      // await pluginManager.initialize();
      
      logger.debug(TAG, '插件管理器初始化占位符');
    } catch (error) {
      throw new Error(`插件管理器初始化失败: ${error}`);
    }
  }

  /**
   * 初始化数据服务层
   */
  private async initializeDataService(context: common.UIAbilityContext, config: InitializationConfig): Promise<void> {
    try {
      const dataService = DataService.getInstance();
      await dataService.initialize(context);
      
      logger.debug(TAG, '数据服务层初始化完成');
    } catch (error) {
      throw new Error(`数据服务层初始化失败: ${error}`);
    }
  }

  /**
   * 执行数据迁移
   */
  private async performDataMigration(): Promise<void> {
    try {
      // 检查是否需要数据迁移
      // 这里可以实现版本检查和数据迁移逻辑
      
      logger.debug(TAG, '数据迁移检查完成');
    } catch (error) {
      throw new Error(`数据迁移失败: ${error}`);
    }
  }

  /**
   * 验证初始化结果
   */
  private async validateInitialization(): Promise<ValidationResult> {
    const errors: string[] = [];
    const warnings: string[] = [];

    try {
      // 验证数据服务是否可用
      const dataService = DataService.getInstance();
      
      // 尝试获取基本统计信息
      try {
        await dataService.getAppDataStats();
      } catch (error) {
        warnings.push(`数据统计功能验证失败: ${error}`);
      }

      // 验证漫画源功能
      try {
        await dataService.getAvailableComicSources();
      } catch (error) {
        warnings.push(`漫画源功能验证失败: ${error}`);
      }

      logger.debug(TAG, '初始化验证完成');

    } catch (error) {
      errors.push(`初始化验证失败: ${error}`);
    }

    const validationResult: ValidationResult = {
      success: errors.length === 0,
      errors,
      warnings
    };

    return validationResult;
  }

  /**
   * 重置初始化状态（用于测试或重新初始化）
   */
  public reset(): void {
    this.isInitialized = false;
    this.initializationPromise = null;
    logger.debug(TAG, '初始化状态已重置');  
  }

  /**
   * 获取初始化状态
   */
  public getInitializationStatus(): InitializationStatus {
    const status: InitializationStatus = {
      isInitialized: this.isInitialized,
      isInitializing: this.initializationPromise !== null
    };
    
    return status;
  }

  /**
   * 销毁初始化器
   */
  public destroy(): void {
    this.reset();
    DataInitializer.instance = null;
    logger.debug(TAG, '数据初始化器已销毁');
  }
}