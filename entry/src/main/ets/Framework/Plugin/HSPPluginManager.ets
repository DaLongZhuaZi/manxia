// 文件路径: src/main/ets/Framework/Plugin/HSPPluginManager.ets
/**
 * HSP插件管理器
 * 实现图源插件的差分更新和热插拔功能
 */

import { bundleManager } from '@kit.AbilityKit';
import { logger } from '../../Utils/Logger';
import { SandboxManager } from '../Storage/SandboxManager';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';

const TAG = 'HSPPluginManager';

/**
 * HapModuleInfo属性访问接口
 */
interface HapModuleInfoAccess {
  moduleType?: number;
  name?: string;
  bundleName?: string;
}

/**
 * 插件配置接口
 */
export interface PluginConfig {
  id: string;
  name: string;
  version: string;
  description: string;
  author: string;
  website: string;
  supportedSites: string[];
  capabilities: PluginCapability[];
}

/**
 * 插件参数接口 - 使用Record类型替代索引签名
 */
export interface PluginParameters extends Record<string, string | number | boolean> {
}

/**
 * 插件模块接口 - 使用Record类型替代索引签名
 */
export interface PluginModule extends Record<string, (parameters: PluginParameters) => Promise<string | number | boolean | PluginParameters>> {
}

export interface PluginInfo {
  id: string;
  name: string;
  version: string;
  description: string;
  author: string;
  website: string;
  supportedSites: string[];
  capabilities: PluginCapability[];
  bundleName: string;
  moduleName: string;
  isEnabled: boolean;
  isInstalled: boolean;
  installTime: number;
  updateTime: number;
  fileSize: number;
  checksum: string;
}

export interface PluginCapability {
  type: 'search' | 'detail' | 'chapter' | 'image';
  version: string;
  parameters: PluginParameters;
}

export interface PluginUpdateInfo {
  pluginId: string;
  currentVersion: string;
  latestVersion: string;
  updateSize: number;
  updateType: 'full' | 'differential';
  changeLog: string;
  downloadUrl: string;
  checksum: string;
  dependencies: string[];
}

export interface DifferentialPatch {
  patchId: string;
  sourceVersion: string;
  targetVersion: string;
  patchSize: number;
  patchData: ArrayBuffer;
  operations: PatchOperation[];
}

export interface PatchOperation {
  type: 'add' | 'modify' | 'delete';
  filePath: string;
  offset?: number;
  length?: number;
  data?: ArrayBuffer;
}

export interface PluginExecutionContext {
  pluginId: string;
  method: string;
  parameters: PluginParameters;
  timeout: number;
}

export interface PluginExecutionResult {
  success: boolean;
  data?: string | number | boolean | PluginParameters;
  error?: string;
  executionTime: number;
}

/**
 * 插件注册表项接口 - 直接使用PluginInfo类型
 */
export type PluginRegistryEntry = PluginInfo;

/**
 * 插件统计信息接口
 */
export interface PluginStats {
  totalPlugins: number;
  enabledPlugins: number;
  loadedPlugins: number;
  updateAvailable: number;
}

export class HSPPluginManager {
  private static instance: HSPPluginManager | null = null;
  private sandboxManager: SandboxManager;
  
  // 插件注册表
  private pluginRegistry = new Map<string, PluginInfo>();
  
  // 已加载的插件模块
  private loadedPlugins = new Map<string, PluginModule>();
  
  // 插件执行上下文
  private executionContexts = new Map<string, PluginExecutionContext>();
  
  // 更新任务队列
  private updateQueue: PluginUpdateInfo[] = [];
  private isUpdating = false;

  private constructor() {
    this.sandboxManager = SandboxManager.getInstance();
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): HSPPluginManager {
    if (!HSPPluginManager.instance) {
      HSPPluginManager.instance = new HSPPluginManager();
    }
    return HSPPluginManager.instance;
  }

  /**
   * 初始化插件管理器
   */
  public async initialize(): Promise<void> {
    try {
      // 扫描已安装的插件
      await this.scanInstalledPlugins();
      
      // 加载插件注册表
      await this.loadPluginRegistry();
      
      // 启动插件
      await this.startEnabledPlugins();
      
      logger.info(TAG, '插件管理器初始化完成');
    } catch (error) {
      logger.error(TAG, '插件管理器初始化失败' + String(error));
      if (error instanceof Error) {
        throw error;
      } else {
        throw new Error('插件管理器初始化失败: 未知错误');
      }
    }
  }

  /**
   * 扫描已安装的插件
   */
  private async scanInstalledPlugins(): Promise<void> {
    try {
      const bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_HAP_MODULE);
      
      for (const hapModuleInfo of bundleInfo.hapModulesInfo) {
        // 使用明确的接口替代对象字面量类型声明
        const moduleAccess = hapModuleInfo as HapModuleInfoAccess;
        if (moduleAccess.moduleType === bundleManager.ModuleType.SHARED) {
          await this.registerHSPPlugin(hapModuleInfo);
        }
      }
      
      logger.info(TAG, `扫描到 ${this.pluginRegistry.size} 个插件`);
    } catch (error) {
      logger.error(TAG, '扫描已安装插件失败' + String(error));
    }
  }

  /**
   * 注册HSP插件
   */
  private async registerHSPPlugin(hapModuleInfo: bundleManager.HapModuleInfo): Promise<void> {
    try {
      // 使用明确的接口替代对象字面量类型声明
      const moduleAccess = hapModuleInfo as HapModuleInfoAccess;
      const moduleName = moduleAccess.name || '';
      const bundleName = moduleAccess.bundleName || '';
      
      // 读取插件配置
      const pluginConfig = await this.loadPluginConfig(moduleName);
      
      if (pluginConfig) {
        const pluginInfo: PluginInfo = {
          id: pluginConfig.id,
          name: pluginConfig.name,
          version: pluginConfig.version,
          description: pluginConfig.description,
          author: pluginConfig.author,
          website: pluginConfig.website,
          supportedSites: pluginConfig.supportedSites,
          capabilities: pluginConfig.capabilities,
          bundleName: bundleName,
          moduleName: moduleName,
          isEnabled: true,
          isInstalled: true,
          installTime: Date.now(),
          updateTime: Date.now(),
          fileSize: 0,
          checksum: ''
        };
        
        this.pluginRegistry.set(pluginInfo.id, pluginInfo);
        logger.debug(TAG, `注册插件: ${pluginInfo.name} v${pluginInfo.version}`);
      }
    } catch (error) {
      const moduleAccess = hapModuleInfo as HapModuleInfoAccess;
      const moduleName = moduleAccess.name || 'unknown';
      logger.error(TAG, `注册HSP插件失败: ${moduleName}` + String(error));
    }
  }

  /**
   * 加载插件配置
   */
  private async loadPluginConfig(moduleName: string): Promise<PluginConfig | null> {
    try {
      // 从HSP模块的资源中读取配置文件
      const configPath = `@bundle:${moduleName}/resources/rawfile/plugin.json`;
      
      // 这里需要使用资源管理器API来读取HSP模块的资源
      // 由于HarmonyOS的资源管理API限制，这里使用模拟实现
      const mockConfig: PluginConfig = {
        id: `plugin_${moduleName}`,
        name: `Plugin ${moduleName}`,
        version: '1.0.0',
        description: `Plugin for ${moduleName}`,
        author: 'Plugin Author',
        website: 'https://example.com',
        supportedSites: ['example.com'],
        capabilities: [
          {
            type: 'search',
            version: '1.0',
            parameters: {}
          }
        ]
      };
      
      return mockConfig;
    } catch (error) {
      logger.error(TAG, `加载插件配置失败: ${moduleName}` + String(error));
      return null;
    }
  }

  /**
   * 加载插件注册表
   */
  private async loadPluginRegistry(): Promise<void> {
    try {
      const registryPath = `${this.sandboxManager.getDirectory('plugins')}/registry.json`;
      
      // 先检查文件是否存在，避免不必要的错误日志
      const fileExists = await this.sandboxManager.exists(registryPath);
      if (!fileExists) {
        logger.info(TAG, '插件注册表文件尚未创建，将在首次安装插件时自动生成');
        return;
      }
      
      const registryData = await this.sandboxManager.readFile(registryPath);
      
      if (registryData) {
        // 使用util.TextDecoder将ArrayBuffer转换为string
        const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
        const registryString = decoder.decodeWithStream(new Uint8Array(registryData), { stream: false });
        const registry = JSON.parse(registryString) as Record<string, PluginRegistryEntry>;
        // 使用传统循环替代Object.entries
        const registryKeys = Object.keys(registry);
        for (let i = 0; i < registryKeys.length; i++) {
          const pluginId = registryKeys[i];
          const savedInfo = registry[pluginId];
          const currentInfo = this.pluginRegistry.get(pluginId);
          if (currentInfo) {
            // 手动复制属性替代Object.assign
            currentInfo.id = savedInfo.id;
            currentInfo.name = savedInfo.name;
            currentInfo.version = savedInfo.version;
            currentInfo.description = savedInfo.description;
            currentInfo.author = savedInfo.author;
            currentInfo.website = savedInfo.website;
            currentInfo.supportedSites = savedInfo.supportedSites;
            currentInfo.capabilities = savedInfo.capabilities;
            currentInfo.bundleName = savedInfo.bundleName;
            currentInfo.moduleName = savedInfo.moduleName;
            currentInfo.isEnabled = savedInfo.isEnabled;
            currentInfo.isInstalled = savedInfo.isInstalled;
            currentInfo.installTime = savedInfo.installTime;
            currentInfo.updateTime = savedInfo.updateTime;
            currentInfo.fileSize = savedInfo.fileSize;
            currentInfo.checksum = savedInfo.checksum;
          }
        }
        logger.info(TAG, '插件注册表加载完成');
      } else {
        logger.info(TAG, '插件注册表文件为空，首次运行将自动创建');
      }
    } catch (error) {
      // 捕获其他可能的错误
      const errorMsg = String(error);
      logger.error(TAG, '加载插件注册表失败' + errorMsg);
    }
  }

  /**
   * 保存插件注册表
   */
  private async savePluginRegistry(): Promise<void> {
    try {
      const registryPath = `${this.sandboxManager.getDirectory('plugins')}/registry.json`;
      // 使用Array.from替代Object.fromEntries
      const registryData: Record<string, PluginInfo> = {};
      const registryEntries = Array.from(this.pluginRegistry.entries());
      for (let i = 0; i < registryEntries.length; i++) {
        const entry = registryEntries[i];
        registryData[entry[0]] = entry[1];
      }
      
      await this.sandboxManager.writeFile(registryPath, JSON.stringify(registryData, null, 2));
    } catch (error) {
      logger.error(TAG, '保存插件注册表失败' + String(error));
    }
  }

  /**
   * 启动已启用的插件
   */
  private async startEnabledPlugins(): Promise<void> {
    try {
      // 使用显式属性访问替代解构
      const registryEntries = Array.from(this.pluginRegistry.entries());
      for (let i = 0; i < registryEntries.length; i++) {
        const pluginId = registryEntries[i][0];
        const pluginInfo = registryEntries[i][1];
        if (pluginInfo.isEnabled && pluginInfo.isInstalled) {
          await this.loadPlugin(pluginId);
        }
      }
    } catch (error) {
      logger.error(TAG, '启动已启用插件失败' + String(error));
    }
  }

  /**
   * 加载插件
   */
  public async loadPlugin(pluginId: string): Promise<boolean> {
    try {
      const pluginInfo = this.pluginRegistry.get(pluginId);
      if (!pluginInfo) {
        throw new Error(`插件不存在: ${pluginId}`);
      }
      
      if (this.loadedPlugins.has(pluginId)) {
        logger.debug(TAG, `插件已加载: ${pluginId}`);
        return true;
      }
      
      // 动态导入HSP模块
      const pluginModule = await this.importHSPModule(pluginInfo.moduleName);
      
      if (pluginModule) {
        this.loadedPlugins.set(pluginId, pluginModule);
        logger.info(TAG, `插件加载成功: ${pluginInfo.name}`);
        return true;
      }
      
      return false;
    } catch (error) {
      logger.error(TAG, `加载插件失败: ${pluginId}` + String(error));
      return false;
    }
  }

  /**
   * 卸载插件
   */
  public async unloadPlugin(pluginId: string): Promise<boolean> {
    try {
      const pluginInfo = this.pluginRegistry.get(pluginId);
      if (!pluginInfo) {
        throw new Error(`插件不存在: ${pluginId}`);
      }
      
      // 停止插件执行
      this.executionContexts.delete(pluginId);
      
      // 从内存中移除
      this.loadedPlugins.delete(pluginId);
      
      logger.info(TAG, `插件卸载成功: ${pluginInfo.name}`);
      return true;
    } catch (error) {
      logger.error(TAG, `卸载插件失败: ${pluginId}` + String(error));
      return false;
    }
  }

  /**
   * 动态导入HSP模块
   */
  private async importHSPModule(moduleName: string): Promise<PluginModule | null> {
    try {
      // 使用动态导入语法加载HSP模块
      // 注意：实际的HSP模块导入可能需要不同的语法
      const module = await import(`@bundle:${moduleName}/ets/index`) as PluginModule;
      return module;
    } catch (error) {
      logger.error(TAG, `导入HSP模块失败: ${moduleName}` + String(error));
      return null;
    }
  }

  /**
   * 执行插件方法
   */
  public async executePlugin(
    pluginId: string,
    method: string,
    parameters: PluginParameters,
    timeout: number = 30000
  ): Promise<PluginExecutionResult> {
    const startTime = Date.now();
    
    try {
      const pluginModule = this.loadedPlugins.get(pluginId);
      if (!pluginModule) {
        throw new Error(`插件未加载: ${pluginId}`);
      }
      
      // 创建执行上下文
      const context: PluginExecutionContext = {
        pluginId,
        method,
        parameters,
        timeout
      };
      
      this.executionContexts.set(pluginId, context);
      
      // 执行插件方法
      const result = await Promise.race([
        this.invokePluginMethod(pluginModule, method, parameters),
        this.createTimeoutPromise(timeout)
      ]);
      
      const executionTime = Date.now() - startTime;
      
      logger.debug(TAG, `插件执行成功: ${pluginId}.${method}, 耗时: ${executionTime}ms`);
      
      return {
        success: true,
        data: result,
        executionTime
      };
      
    } catch (error) {
      const executionTime = Date.now() - startTime;
      const errorMessage = error instanceof Error ? error.message : '未知错误';
      logger.error(TAG, `插件执行失败: ${pluginId}.${method}` + String(error));
      
      return {
        success: false,
        error: errorMessage,
        executionTime
      };
    } finally {
      this.executionContexts.delete(pluginId);
    }
  }

  /**
   * 调用插件方法
   */
  private async invokePluginMethod(
    pluginModule: PluginModule,
    method: string,
    parameters: PluginParameters
  ): Promise<string | number | boolean | PluginParameters> {
    // 使用安全的方法检查
    const moduleKeys = Object.keys(pluginModule);
    if (!moduleKeys.includes(method)) {
      throw new Error(`插件方法不存在: ${method}`);
    }
    
    const methodValue = pluginModule[method];
    if (typeof methodValue !== 'function') {
      throw new Error(`插件方法不是函数: ${method}`);
    }
    
    const methodFunction = methodValue as (parameters: PluginParameters) => Promise<string | number | boolean | PluginParameters>;
    return await methodFunction(parameters);
  }

  /**
   * 创建超时Promise
   */
  private createTimeoutPromise(timeout: number): Promise<never> {
    return new Promise((_, reject) => {
      setTimeout(() => {
        reject(new Error(`插件执行超时: ${timeout}ms`));
      }, timeout);
    });
  }

  /**
   * 检查插件更新
   */
  public async checkPluginUpdates(): Promise<PluginUpdateInfo[]> {
    try {
      const updateInfos: PluginUpdateInfo[] = [];
      
      // 使用显式属性访问替代解构
      const registryEntries = Array.from(this.pluginRegistry.entries());
      for (let i = 0; i < registryEntries.length; i++) {
        const pluginId = registryEntries[i][0];
        const pluginInfo = registryEntries[i][1];
        // 模拟检查更新逻辑
        const updateInfo = await this.checkSinglePluginUpdate(pluginInfo);
        if (updateInfo) {
          updateInfos.push(updateInfo);
        }
      }
      
      logger.info(TAG, `检查到 ${updateInfos.length} 个插件更新`);
      return updateInfos;
    } catch (error) {
      logger.error(TAG, '检查插件更新失败' + String(error));
      return [];
    }
  }

  /**
   * 检查单个插件更新
   */
  private async checkSinglePluginUpdate(pluginInfo: PluginInfo): Promise<PluginUpdateInfo | null> {
    try {
      // 模拟从服务器获取更新信息
      const mockUpdateInfo: PluginUpdateInfo = {
        pluginId: pluginInfo.id,
        currentVersion: pluginInfo.version,
        latestVersion: '1.1.0',
        updateSize: 1024 * 1024, // 1MB
        updateType: 'differential',
        changeLog: '修复了一些问题，提升了性能',
        downloadUrl: `https://example.com/plugins/${pluginInfo.id}/update.hsp`,
        checksum: 'mock_checksum',
        dependencies: []
      };
      
      // 检查版本是否需要更新
      if (this.compareVersions(mockUpdateInfo.latestVersion, pluginInfo.version) > 0) {
        return mockUpdateInfo;
      }
      
      return null;
    } catch (error) {
      logger.error(TAG, `检查插件更新失败: ${pluginInfo.id}` + String(error));
      return null;
    }
  }

  /**
   * 更新插件
   */
  public async updatePlugin(updateInfo: PluginUpdateInfo): Promise<void> {
    try {
      logger.info(TAG, `开始更新插件: ${updateInfo.pluginId}`);
      
      // 添加到更新队列
      this.updateQueue.push(updateInfo);
      
      // 如果没有正在更新，开始处理队列
      if (!this.isUpdating) {
        await this.processUpdateQueue();
      }
    } catch (error) {
      logger.error(TAG, `更新插件失败: ${updateInfo.pluginId}` + String(error));
      if (error instanceof Error) {
        throw error;
      } else {
        throw new Error(`更新插件失败: ${updateInfo.pluginId} - 未知错误`);
      }
    }
  }

  /**
   * 处理更新队列
   */
  private async processUpdateQueue(): Promise<void> {
    if (this.isUpdating || this.updateQueue.length === 0) {
      return;
    }
    
    this.isUpdating = true;
    
    try {
      while (this.updateQueue.length > 0) {
        const updateInfo = this.updateQueue.shift();
        if (updateInfo) {
          await this.performPluginUpdate(updateInfo);
        }
      }
    } catch (error) {
      logger.error(TAG, '处理更新队列失败' + String(error));
    } finally {
      this.isUpdating = false;
    }
  }

  /**
   * 执行插件更新
   */
  private async performPluginUpdate(updateInfo: PluginUpdateInfo): Promise<void> {
    try {
      // 先卸载旧版本
      await this.unloadPlugin(updateInfo.pluginId);
      
      // 根据更新类型选择更新方式
      if (updateInfo.updateType === 'differential') {
        await this.performDifferentialUpdate(updateInfo);
      } else {
        await this.performFullUpdate(updateInfo);
      }
      
      // 更新插件信息
      const pluginInfo = this.pluginRegistry.get(updateInfo.pluginId);
      if (pluginInfo) {
        pluginInfo.version = updateInfo.latestVersion;
        pluginInfo.updateTime = Date.now();
      }
      
      // 保存注册表
      await this.savePluginRegistry();
      
      logger.info(TAG, `插件更新完成: ${updateInfo.pluginId}`);
    } catch (error) {
      logger.error(TAG, `执行插件更新失败: ${updateInfo.pluginId}` + String(error));
      if (error instanceof Error) {
        throw error;
      } else {
        throw new Error(`执行插件更新失败: ${updateInfo.pluginId} - 未知错误`);
      }
    }
  }

  /**
   * 执行差分更新
   */
  private async performDifferentialUpdate(updateInfo: PluginUpdateInfo): Promise<void> {
    try {
      // 下载差分补丁
      const patchData = await this.downloadPatch(updateInfo.downloadUrl);
      
      // 解析差分补丁
      const patch = await this.parseDifferentialPatch(patchData);
      
      // 应用差分补丁
      await this.applyDifferentialPatch(updateInfo.pluginId, patch);
      
      logger.info(TAG, `差分更新完成: ${updateInfo.pluginId}`);
    } catch (error) {
      logger.error(TAG, `差分更新失败: ${updateInfo.pluginId}` + String(error));
      if (error instanceof Error) {
        throw error;
      } else {
        throw new Error(`差分更新失败: ${updateInfo.pluginId} - 未知错误`);
      }
    }
  }

  /**
   * 执行完整更新
   */
  private async performFullUpdate(updateInfo: PluginUpdateInfo): Promise<void> {
    try {
      // 下载完整插件包
      const packageData = await this.downloadPackage(updateInfo.downloadUrl);
      
      // 验证校验和
      const calculatedChecksum = await this.calculateChecksum(packageData);
      if (calculatedChecksum !== updateInfo.checksum) {
        throw new Error('插件包校验和不匹配');
      }
      
      // 安装新版本
      await this.installPluginPackage(updateInfo.pluginId, packageData);
      
      logger.info(TAG, `完整更新完成: ${updateInfo.pluginId}`);
    } catch (error) {
      logger.error(TAG, `完整更新失败: ${updateInfo.pluginId}` + String(error));
      if (error instanceof Error) {
        throw error;
      } else {
        throw new Error(`完整更新失败: ${updateInfo.pluginId} - 未知错误`);
      }
    }
  }

  /**
   * 下载补丁
   */
  private async downloadPatch(url: string): Promise<ArrayBuffer> {
    // 模拟下载补丁的逻辑
    logger.debug(TAG, `下载补丁: ${url}`);
    return new ArrayBuffer(0);
  }

  /**
   * 下载插件包
   */
  private async downloadPackage(url: string): Promise<ArrayBuffer> {
    // 模拟下载插件包的逻辑
    logger.debug(TAG, `下载插件包: ${url}`);
    return new ArrayBuffer(0);
  }

  /**
   * 计算校验和
   */
  private async calculateChecksum(data: ArrayBuffer): Promise<string> {
    // 模拟计算校验和的逻辑
    return 'mock_checksum';
  }

  /**
   * 解析差分补丁
   */
  private async parseDifferentialPatch(patchData: ArrayBuffer): Promise<DifferentialPatch> {
    // 模拟解析差分补丁的逻辑
    return {
      patchId: 'mock_patch',
      sourceVersion: '1.0.0',
      targetVersion: '1.1.0',
      patchSize: patchData.byteLength,
      patchData: patchData,
      operations: []
    };
  }

  /**
   * 应用差分补丁
   */
  private async applyDifferentialPatch(pluginId: string, patch: DifferentialPatch): Promise<void> {
    try {
      logger.debug(TAG, `应用差分补丁: ${pluginId}`);
      
      // 应用补丁操作
      for (const operation of patch.operations) {
        await this.applyPatchOperation(pluginId, operation);
      }
      
      // 重新加载插件
      await this.loadPlugin(pluginId);
      
    } catch (error) {
      logger.error(TAG, `应用差分补丁失败: ${pluginId}` + String(error));
      if (error instanceof Error) {
        throw error;
      } else {
        throw new Error(`应用差分补丁失败: ${pluginId} - 未知错误`);
      }
    }
  }

  /**
   * 应用补丁操作
   */
  private async applyPatchOperation(pluginId: string, operation: PatchOperation): Promise<void> {
    const pluginDir = `${this.sandboxManager.getDirectory('plugins')}/${pluginId}`;
    const targetPath = `${pluginDir}/${operation.filePath}`;
    
    switch (operation.type) {
      case 'add':
        if (operation.data) {
          await this.sandboxManager.writeFile(targetPath, operation.data);
        }
        break;
        
      case 'modify':
        if (operation.data) {
          await this.sandboxManager.writeFile(targetPath, operation.data);
        }
        break;
        
      case 'delete':
        if (await this.sandboxManager.exists(targetPath)) {
          await this.sandboxManager.deleteFile(targetPath);
        }
        break;
    }
  }

  /**
   * 安装插件包
   */
  private async installPluginPackage(pluginId: string, packageData: ArrayBuffer): Promise<void> {
    // 模拟安装插件包的逻辑
    // 实际实现需要解压HSP包并安装到系统中
    logger.debug(TAG, `安装插件包: ${pluginId}`);
  }

  /**
   * 比较版本号
   */
  private compareVersions(version1: string, version2: string): number {
    const v1Parts = version1.split('.').map(Number);
    const v2Parts = version2.split('.').map(Number);
    
    const maxLength = Math.max(v1Parts.length, v2Parts.length);
    
    for (let i = 0; i < maxLength; i++) {
      const v1Part = v1Parts[i] || 0;
      const v2Part = v2Parts[i] || 0;
      
      if (v1Part > v2Part) return 1;
      if (v1Part < v2Part) return -1;
    }
    
    return 0;
  }

  /**
   * 获取所有插件信息
   */
  public getAllPlugins(): PluginInfo[] {
    return Array.from(this.pluginRegistry.values());
  }

  /**
   * 获取已启用的插件
   */
  public getEnabledPlugins(): PluginInfo[] {
    return Array.from(this.pluginRegistry.values()).filter(plugin => plugin.isEnabled);
  }

  /**
   * 启用插件
   */
  public async enablePlugin(pluginId: string): Promise<boolean> {
    try {
      const pluginInfo = this.pluginRegistry.get(pluginId);
      if (!pluginInfo) {
        throw new Error(`插件不存在: ${pluginId}`);
      }
      
      pluginInfo.isEnabled = true;
      await this.loadPlugin(pluginId);
      await this.savePluginRegistry();
      
      logger.info(TAG, `插件已启用: ${pluginInfo.name}`);
      return true;
    } catch (error) {
      logger.error(TAG, `启用插件失败: ${pluginId}` + String(error));
      return false;
    }
  }

  /**
   * 禁用插件
   */
  public async disablePlugin(pluginId: string): Promise<boolean> {
    try {
      const pluginInfo = this.pluginRegistry.get(pluginId);
      if (!pluginInfo) {
        throw new Error(`插件不存在: ${pluginId}`);
      }
      
      pluginInfo.isEnabled = false;
      await this.unloadPlugin(pluginId);
      await this.savePluginRegistry();
      
      logger.info(TAG, `插件已禁用: ${pluginInfo.name}`);
      return true;
    } catch (error) {
      logger.error(TAG, `禁用插件失败: ${pluginId}` + String(error));
      return false;
    }
  }

  /**
   * 获取插件统计信息
   */
  public getPluginStats(): PluginStats {
    const totalPlugins = this.pluginRegistry.size;
    const enabledPlugins = Array.from(this.pluginRegistry.values()).filter(p => p.isEnabled).length;
    const loadedPlugins = this.loadedPlugins.size;
    const updateAvailable = 0; // 需要实现更新检查逻辑
    
    return {
      totalPlugins,
      enabledPlugins,
      loadedPlugins,
      updateAvailable
    };
  }
}