/**
 * WebView源管理器实现
 * 管理漫画源的WebView实例、配置和生命周期
 * 符合HarmonyOS API 18和ArkTS规范
 */

import { webview } from '@kit.ArkWeb';
import { logger } from '../../Utils/Logger';
import { DatabaseManager } from '../Database/DatabaseManager';
import { 
  ComicSourceDatabaseRecord,
  DatabaseValue,
  UpdateRecordData,
  WebViewSourceConfigDatabaseRecord
} from '../Database/DatabaseTypes';
import { 
  IWebViewSourceManager,
  WebViewSourceConfig,
  WebViewConfigFactory
} from './WebViewImageLoader';
import { GlobalWebViewContainer, WebViewEventCallbacks } from './WebViewContainerPage';
import { MangaSourceEngine, EngineConfig } from './MangaSourceEngine';
import { AntiCrawlerConfig } from './MangaSourceTypes';
import { DataManager } from '../Data/DataManager';
import { WebViewAuthManager } from './WebViewAuthManager';

const TAG = 'WebViewSourceManager';

/**
 * WebView实例信息接口
 */
interface WebViewInstanceInfo {
  /** WebView控制器 */
  readonly controller: webview.WebviewController;
  /** 源配置 */
  readonly config: WebViewSourceConfig;
  /** 创建时间 */
  readonly createTime: number;
  /** 最后使用时间 */
  lastUsedTime: number;
  /** 是否正在使用 */
  isInUse: boolean;
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
 * WebView源管理器实现类
 */
export class WebViewSourceManager implements IWebViewSourceManager {
  private static instance: WebViewSourceManager | null = null;
  private readonly sourceConfigs: Map<string, WebViewSourceConfig> = new Map();
  private readonly webViewInstances: Map<string, WebViewInstanceInfo> = new Map();
  private readonly databaseManager: DatabaseManager;
  private readonly dataManager: DataManager;
  private isInitialized: boolean = false;
  private cleanupTimer: number | null = null;
  
  // 新增：MangaSourceEngine实例管理
  private readonly mangaEngines: Map<number, MangaSourceEngine> = new Map();
  private globalWebViewController: webview.WebviewController | null = null;

  /**
   * 私有构造函数
   */
  private constructor() {
    this.databaseManager = DatabaseManager.getInstance();
    this.dataManager = DataManager.getInstance();
  }

  /**
   * 导航指定源的WebView到URL
   */
  navigateSourceWebView(sourceId: string, url: string): void {
    const info = this.webViewInstances.get(sourceId);
    if (!info) {
      logger.warn(TAG, `WebView实例不存在: ${sourceId}`);
      return;
    }
    info.controller.loadUrl(url);
  }

  /**
   * 获取单例实例
   */
  static getInstance(): WebViewSourceManager {
    if (!WebViewSourceManager.instance) {
      WebViewSourceManager.instance = new WebViewSourceManager();
    }
    return WebViewSourceManager.instance;
  }

  /**
   * 初始化管理器
   */
  async initialize(): Promise<void> {
    if (this.isInitialized) {
      return;
    }

    try {
      logger.info(TAG, '开始初始化WebView源管理器');
      
      // 从数据库加载所有源配置
      await this.loadSourceConfigsFromDatabase();
      
      // 启动清理定时器
      this.startCleanupTimer();
      
      this.isInitialized = true;
      logger.info(TAG, `WebView源管理器初始化完成，加载了${this.sourceConfigs.size}个源配置`);
      
    } catch (error) {
      logger.error(TAG, `初始化WebView源管理器失败: ${error instanceof Error ? error.message : String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 初始化源配置
   */
  initializeSource(sourceRecord: ComicSourceDatabaseRecord): void {
    try {
      logger.info(TAG, `初始化源配置: ${sourceRecord.name} (${sourceRecord.id})`);
      
      // 创建源配置
      const config = WebViewConfigFactory.createFromDatabaseRecord(sourceRecord);
      this.sourceConfigs.set(sourceRecord.id, config);
      
      logger.info(TAG, `源配置初始化完成: ${sourceRecord.name}`);
      
    } catch (error) {
      logger.error(TAG, `初始化源配置失败: ${sourceRecord.name}, 错误: ${error instanceof Error ? error.message : String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 更新源配置
   */
  async updateSourceConfig(sourceId: string, configUpdate: WebViewConfigUpdate): Promise<void> {
    try {
      const existingConfig = this.sourceConfigs.get(sourceId);
      if (!existingConfig) {
        throw new Error(`源配置不存在: ${sourceId}`);
      }

      // 合并配置
      const updatedConfig: WebViewSourceConfig = {
        sourceId: existingConfig.sourceId,
        userAgent: configUpdate.userAgent || existingConfig.userAgent,
        enableJavaScript: configUpdate.enableJavaScript !== undefined ? 
          configUpdate.enableJavaScript : existingConfig.enableJavaScript,
        enableImages: configUpdate.enableImages !== undefined ? 
          configUpdate.enableImages : existingConfig.enableImages,
        cookiePolicy: configUpdate.cookiePolicy || existingConfig.cookiePolicy,
        timeout: configUpdate.timeout || existingConfig.timeout
      };

      // 更新内存中的配置
      this.sourceConfigs.set(sourceId, updatedConfig);

      // 销毁现有WebView实例，下次使用时重新创建
      this.destroyWebViewInstance(sourceId);

      // 更新数据库中的配置
      await this.updateSourceConfigInDatabase(sourceId, updatedConfig);

      logger.info(TAG, `源配置更新完成: ${sourceId}`);

    } catch (error) {
      logger.error(TAG, `更新源配置失败: ${sourceId}, 错误: ${error instanceof Error ? error.message : String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 移除源配置
   */
  removeSource(sourceId: string): void {
    try {
      // 销毁WebView实例
      this.destroyWebViewInstance(sourceId);
      
      // 移除配置
      this.sourceConfigs.delete(sourceId);
      
      logger.info(TAG, `源配置移除完成: ${sourceId}`);
      
    } catch (error) {
      logger.error(TAG, `移除源配置失败: ${sourceId}, 错误: ${error instanceof Error ? error.message : String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 获取所有源ID
   */
  getAllSourceIds(): string[] {
    return Array.from(this.sourceConfigs.keys());
  }

  /**
   * 获取源配置
   */
  getSourceConfig(sourceId: string): WebViewSourceConfig | null {
    const cfg = this.sourceConfigs.get(sourceId);
    return cfg ? cfg : null;
  }

  /**
   * 获取WebView实例
   */
  getWebViewInstance(sourceId: string): webview.WebviewController | null {
    try {
      let instanceInfo: WebViewInstanceInfo | undefined = this.webViewInstances.get(sourceId);
      
      if (!instanceInfo) {
        // 创建新实例
        const newInstanceInfo = this.createWebViewInstance(sourceId);
        if (!newInstanceInfo) {
          return null;
        }
        instanceInfo = newInstanceInfo;
      }
      
      // 更新使用时间
      instanceInfo.lastUsedTime = Date.now();
      instanceInfo.isInUse = true;
      
      return instanceInfo.controller;
      
    } catch (error) {
      logger.error(TAG, `获取WebView实例失败: ${sourceId}, 错误: ${error instanceof Error ? error.message : String(error)}`);
      return null;
    }
  }

  /**
   * 释放WebView实例
   */
  releaseWebViewInstance(sourceId: string): void {
    const instanceInfo = this.webViewInstances.get(sourceId);
    if (instanceInfo) {
      instanceInfo.isInUse = false;
      instanceInfo.lastUsedTime = Date.now();
    }
  }
  
  /**
   * 获取或创建MangaSourceEngine实例
   * [修复] 支持按图源名称降级查找
   * @param sourceId 图源ID（数字类型）
   * @param sourceName 图源名称（可选，用于降级查找）
   * @returns MangaSourceEngine实例
   */
  async getMangaEngine(sourceId: number, sourceName?: string): Promise<MangaSourceEngine> {
    try {
      // 检查缓存
      if (this.mangaEngines.has(sourceId)) {
        logger.debug(TAG, `使用缓存的MangaSourceEngine: ${sourceId}`);
        return this.mangaEngines.get(sourceId)!;
      }
      
      // 创建新引擎（传递图源名称用于降级查找）
      logger.info(TAG, `创建新的MangaSourceEngine: ${sourceId}${sourceName ? ` (名称: ${sourceName})` : ''}`);
      const engine = await this.createMangaEngine(sourceId, sourceName);
      this.mangaEngines.set(sourceId, engine);
      
      return engine;
    } catch (error) {
      logger.error(TAG, `获取MangaSourceEngine失败: ${sourceId}, 错误: ${error instanceof Error ? error.message : String(error)}`);
      throw error as Error;
    }
  }
  
  /**
   * 检测图源是否为WebView类型
   * @param sourceId 图源ID
   * @returns 是否为WebView类型
   */
  async isWebViewSource(sourceId: number): Promise<boolean> {
    try {
      const config: ESObject | null = await this.dataManager.getSourceConfig(sourceId);
      return !!config && !!config.workflows;
    } catch (error) {
      logger.error(TAG, `检测图源类型失败: ${sourceId}, 错误: ${error instanceof Error ? error.message : String(error)}`);
      return false;
    }
  }
  
  /**
   * 设置全局WebView控制器（由SourceDetailPage提供）
   */
  setGlobalWebViewController(controller: webview.WebviewController): void {
    logger.info(TAG, '设置全局WebView控制器');
    this.globalWebViewController = controller;
    
    // 更新所有已缓存的Engine的WebView控制器
    this.updateAllEnginesWebView(controller);
  }
  
  /**
   * 更新所有已缓存Engine的WebView控制器
   */
  private updateAllEnginesWebView(controller: webview.WebviewController): void {
    const engineCount = this.mangaEngines.size;
    if (engineCount === 0) {
      return;
    }
    
    logger.info(TAG, `更新 ${engineCount} 个缓存Engine的WebView控制器`);
    const engines = Array.from(this.mangaEngines.entries());
    for (let i = 0; i < engines.length; i++) {
      const entry = engines[i];
      const sourceId: number = entry[0];
      const engine: MangaSourceEngine = entry[1];
      try {
        engine.updateWebViewController(controller);
        logger.debug(TAG, `Engine ${sourceId} WebView已更新`);
      } catch (error) {
        logger.warn(TAG, `Engine ${sourceId} WebView更新失败: ${String(error)}`);
      }
    }
  }
  
  /**
   * 获取全局WebView控制器（所有引擎共享）
   */
  getGlobalWebViewController(): webview.WebviewController | null {
    if (!this.globalWebViewController) {
      logger.warn(TAG, '全局WebView控制器未设置');
    }
    return this.globalWebViewController;
  }
  
  /**
   * 创建MangaSourceEngine实例
   * [修复] 支持按图源名称降级查找，提高图源管理的灵活性
   */
  private async createMangaEngine(sourceId: number, sourceName?: string): Promise<MangaSourceEngine> {
    try {
      let config: ESObject | null = null;
      let actualSourceId: number = sourceId;
      
      // 优先按 ID 查找
      config = await this.dataManager.getSourceConfig(sourceId);
      
      // 如果按 ID 查找失败，且提供了图源名称，则按名称降级查找
      if (!config && sourceName) {
        logger.warn(TAG, `图源ID ${sourceId} 不存在，尝试按名称查找: "${sourceName}"`);
        const result = await this.dataManager.getSourceConfigByName(sourceName);
        if (result) {
          config = result.config;
          actualSourceId = result.id;
          logger.info(TAG, `✅ 按名称找到图源: "${sourceName}", 新ID=${actualSourceId}`);
        }
      }
      
      if (!config) {
        throw new Error(`图源配置不存在: ${sourceId}${sourceName ? ` (名称: ${sourceName})` : ''}`);
      }
      
      // 检查是否为WebView类型
      if (!config.workflows) {
        throw new Error(`图源不是WebView类型: ${actualSourceId}`);
      }
      
      // 配置反爬虫策略
      const antiCrawlerConfig: AntiCrawlerConfig = {
        cloudflare: {
          enabled: true,
          bypassMethod: 'wait'
        },
        captcha: {
          enabled: true,
          autoSolve: false
        },
        ipBlock: {
          enabled: true,
          delay: 3000
        }
      };
      
      // 获取WebView控制器
      const controller = this.getGlobalWebViewController();
      if (!controller) {
        throw new Error('WebView控制器未设置，请先在SourceDetailPage中初始化');
      }
      
      // 配置引擎（使用实际找到的 sourceId）
      const engineConfig: EngineConfig = {
        webViewController: controller,
        antiCrawlerConfig: antiCrawlerConfig,
        debug: true,
        timeout: 30000,
        caseSensitive: false,
        sourceId: actualSourceId
      };
      
      // 创建引擎实例
      const engine = new MangaSourceEngine(engineConfig);
      
      // 加载配置
      const configJson = JSON.stringify(config);
      await engine.loadConfig(configJson);
      
      logger.info(TAG, `MangaSourceEngine创建成功: ${actualSourceId}${actualSourceId !== sourceId ? ` (原ID: ${sourceId})` : ''}`);
      return engine;
      
    } catch (error) {
      logger.error(TAG, `创建MangaSourceEngine失败: ${sourceId}, 错误: ${error instanceof Error ? error.message : String(error)}`);
      throw error as Error;
    }
  }
  
  /**
   * 释放MangaSourceEngine实例
   */
  releaseMangaEngine(sourceId: number): void {
    if (this.mangaEngines.has(sourceId)) {
      logger.info(TAG, `释放MangaSourceEngine: ${sourceId}`);
      this.mangaEngines.delete(sourceId);
    }
  }

  /**
   * 从数据库加载源配置
   */
  private async loadSourceConfigsFromDatabase(): Promise<void> {
    try {
      const sources: ComicSourceDatabaseRecord[] = await this.databaseManager.query<ComicSourceDatabaseRecord>(
        'comic_source',
        undefined,
        'isEnabled = ?',
        [1]
      );

      for (const source of sources) {
        const config = WebViewConfigFactory.createFromDatabaseRecord(source);
        this.sourceConfigs.set(source.id, config);
      }

      logger.info(TAG, `从数据库加载了${sources.length}个源配置`);

    } catch (error) {
      logger.error(TAG, `从数据库加载源配置失败: ${error instanceof Error ? error.message : String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 创建WebView实例
   */
  private createWebViewInstance(sourceId: string): WebViewInstanceInfo | null {
    try {
      const config = this.sourceConfigs.get(sourceId);
      if (!config) {
        logger.warn(TAG, `源配置不存在，无法创建WebView实例: ${sourceId}`);
        return null;
      }

      // 创建WebView控制器
      const controller = new webview.WebviewController();
      
      // 创建事件回调
      const callbacks: WebViewEventCallbacks = {
        onPageBegin: (url: string) => {
          logger.debug(TAG, `[${sourceId}] 页面开始加载: ${url}`);
          const sid: number = Number(sourceId);
          WebViewAuthManager.getInstance().applyCookiesToController(sid, controller);
        },
        onPageEnd: (url: string) => {
          logger.debug(TAG, `[${sourceId}] 页面加载完成: ${url}`);
           const sid: number = Number(sourceId);
           WebViewAuthManager.getInstance().captureCookiesFromController(sid, controller);
        },
        onProgressChange: (progress: number) => {
          logger.debug(TAG, `[${sourceId}] 加载进度: ${progress}%`);
        },
        onError: (error: string) => {
          logger.error(TAG, `[${sourceId}] 加载错误: ${error}`);
        },
        onConsoleMessage: (message: string, level: string) => {
          logger.debug(TAG, `[${sourceId}] 控制台[${level}]: ${message}`);
        }
      };

      // 将WebView添加到全局容器中
      GlobalWebViewContainer.addWebView(sourceId, controller, config, callbacks);

      const instanceInfo: WebViewInstanceInfo = {
        controller: controller,
        config: config,
        createTime: Date.now(),
        lastUsedTime: Date.now(),
        isInUse: false
      };

      this.webViewInstances.set(sourceId, instanceInfo);
      
      logger.info(TAG, `WebView实例创建完成并添加到容器: ${sourceId}`);
      return instanceInfo;

    } catch (error) {
      logger.error(TAG, `创建WebView实例失败: ${sourceId}, 错误: ${error instanceof Error ? error.message : String(error)}`);
      return null;
    }
  }

  /**
   * 销毁WebView实例
   */
  private destroyWebViewInstance(sourceId: string): void {
    try {
      const instanceInfo = this.webViewInstances.get(sourceId);
      if (instanceInfo) {
        // 从全局容器中移除WebView组件
        GlobalWebViewContainer.removeWebView(sourceId);
        
        // 移除实例
        this.webViewInstances.delete(sourceId);
        
        logger.info(TAG, `WebView实例销毁完成: ${sourceId}`);
      }
    } catch (error) {
      logger.error(TAG, `销毁WebView实例失败: ${sourceId}, 错误: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 更新数据库中的源配置
   */
  private async updateSourceConfigInDatabase(sourceId: string, config: WebViewSourceConfig): Promise<void> {
    try {
      const updateData: UpdateRecordData = {
        id: sourceId,
        userAgent: config.userAgent,
        enableJavaScript: config.enableJavaScript ? 1 : 0,
        enableImages: config.enableImages ? 1 : 0,
        timeout: config.timeout,
        lastUpdateTime: Date.now().toString()
      };

      await this.databaseManager.update(
        'comic_source',
        updateData,
        'id = ?',
        [sourceId]
      );

      logger.debug(TAG, `数据库中的源配置更新完成: ${sourceId}`);

    } catch (error) {
      logger.error(TAG, `更新数据库中的源配置失败: ${sourceId}, 错误: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 启动清理定时器
   */
  private startCleanupTimer(): void {
    // 使用递归调度替代setInterval，符合ArkTS规范
    this.scheduleCleanup();
  }

  /**
   * 递归调度清理任务
   */
  private scheduleCleanup(): void {
    // 每5分钟清理一次未使用的WebView实例
    const scheduleNext = (): void => {
      this.cleanupUnusedInstances();
      if (this.cleanupTimer !== null) {
        this.scheduleCleanup();
      }
    };
    
    // 使用setTimeout模拟setInterval的递归调度
    this.cleanupTimer = setTimeout(scheduleNext, 5 * 60 * 1000);
  }

  /**
   * 清理未使用的WebView实例
   */
  private cleanupUnusedInstances(): void {
    const now = Date.now();
    const maxIdleTime = 10 * 60 * 1000; // 10分钟

    const instancesToRemove: string[] = [];

    this.webViewInstances.forEach((instanceInfo, sourceId) => {
      if (!instanceInfo.isInUse && (now - instanceInfo.lastUsedTime) > maxIdleTime) {
        instancesToRemove.push(sourceId);
      }
    });

    instancesToRemove.forEach(sourceId => {
      this.destroyWebViewInstance(sourceId);
    });

    if (instancesToRemove.length > 0) {
      logger.info(TAG, `清理了${instancesToRemove.length}个未使用的WebView实例`);
    }
  }

  /**
   * 清理资源
   */
  cleanup(): void {
    logger.info(TAG, '清理WebView源管理器资源');
    
    // 停止清理定时器
    if (this.cleanupTimer) {
      clearTimeout(this.cleanupTimer);
      this.cleanupTimer = null;
    }
    
    // 销毁所有WebView实例
    const sourceIds = Array.from(this.webViewInstances.keys());
    sourceIds.forEach(sourceId => {
      this.destroyWebViewInstance(sourceId);
    });
    
    // 清理MangaSourceEngine实例
    this.mangaEngines.clear();
    
    // 清理全局WebView控制器
    if (this.globalWebViewController) {
      this.globalWebViewController = null;
    }
    
    // 清理配置
    this.sourceConfigs.clear();
    
    this.isInitialized = false;
  }
}
