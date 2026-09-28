// 文件路径: src/main/ets/Utils/NativeModuleManager.ets
/**
 * 本地模块管理器模块
 * 负责管理应用的本地模块（如XComponent），
 * 提供模块注册、获取和调用功能。
 */

import { logger } from './Logger';

/**
 * Native模块接口定义
 */
export interface NativeXComponentModule {
  drawRectangle: (componentId: string) => void;
  changeColor?: (componentId: string) => void;
}

/**
 * Native模块管理器单例类
 * 替代globalThis访问，提供类型安全的Native模块管理
 */
export class NativeModuleManager {
  private static instance: NativeModuleManager | undefined = undefined;
  private nativeModules: Map<string, NativeXComponentModule> = new Map();
  private globalObject: Record<string, Function> | undefined = undefined;

  private constructor() {
    this.initializeGlobalObject();
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): NativeModuleManager {
    if (!NativeModuleManager.instance) {
      NativeModuleManager.instance = new NativeModuleManager();
    }
    return NativeModuleManager.instance;
  }

  /**
   * 初始化全局对象访问
   */
  private initializeGlobalObject(): void {
    try {
      // 使用间接方式获取全局对象，避免直接使用globalThis
      const getGlobal = new Function('return this') as () => Record<string, Function>;
      const globalObj: Record<string, Function> = getGlobal();
      
      if (globalObj && typeof globalObj === 'object') {
        this.globalObject = globalObj;
        logger.debug('NativeModuleManager', '全局对象初始化成功');
      } else {
        logger.error('NativeModuleManager', '无法获取全局对象');
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('NativeModuleManager', `全局对象初始化失败: ${errorMessage}`);
    }
  }

  /**
   * 获取Native模块
   * @param moduleName 模块名称
   * @returns Native模块实例或undefined
   */
  public getNativeModule(moduleName: string): NativeXComponentModule | undefined {
    try {
      // 先从缓存中查找
      if (this.nativeModules.has(moduleName)) {
        return this.nativeModules.get(moduleName);
      }

      // 从全局对象中获取requireNapi函数
      if (!this.globalObject) {
        logger.error('NativeModuleManager', '全局对象未初始化');
        return undefined;
      }

      const requireNapi = this.globalObject['requireNapi'];
      if (typeof requireNapi !== 'function') {
        logger.error('NativeModuleManager', 'requireNapi函数不存在');
        return undefined;
      }

      // 调用requireNapi获取模块
      const nativeModule = requireNapi(moduleName) as NativeXComponentModule;
      if (nativeModule && typeof nativeModule === 'object') {
        // 缓存模块
        this.nativeModules.set(moduleName, nativeModule);
        logger.info('NativeModuleManager', `Native模块 ${moduleName} 加载成功`);
        return nativeModule;
      } else {
        logger.error('NativeModuleManager', `Native模块 ${moduleName} 加载失败`);
        return undefined;
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('NativeModuleManager', `获取Native模块失败: ${errorMessage}`);
      return undefined;
    }
  }

  /**
   * 检查模块是否可用
   * @param moduleName 模块名称
   * @returns 模块是否可用
   */
  public isModuleAvailable(moduleName: string): boolean {
    const module = this.getNativeModule(moduleName);
    return module !== undefined;
  }

  /**
   * 清除模块缓存
   * @param moduleName 模块名称，不传则清除所有缓存
   */
  public clearModuleCache(moduleName?: string): void {
    if (moduleName) {
      this.nativeModules.delete(moduleName);
      logger.debug('NativeModuleManager', `清除模块 ${moduleName} 缓存`);
    } else {
      this.nativeModules.clear();
      logger.debug('NativeModuleManager', '清除所有模块缓存');
    }
  }

  /**
   * 销毁单例实例
   */
  public static destroyInstance(): void {
    if (NativeModuleManager.instance) {
      NativeModuleManager.instance.nativeModules.clear();
      NativeModuleManager.instance = undefined;
      logger.debug('NativeModuleManager', '单例实例已销毁');
    }
  }

  /**
   * 获取已加载的模块列表
   */
  public getLoadedModules(): string[] {
    return Array.from(this.nativeModules.keys());
  }
}