/**
 * WebView源管理器实现
 * 管理漫画源的WebView实例、配置和生命周期
 * 符合HarmonyOS API 18和ArkTS规范
 */

import { webview } from '@kit.ArkWeb';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { DatabaseManager } from 'manxia_core/src/main/ets/Framework/Database/DatabaseManager';
import { 
  ComicSourceDatabaseRecord,
  DatabaseValue,
  UpdateRecordData,
  WebViewSourceConfigDatabaseRecord
} from 'manxia_core/src/main/ets/Framework/Database/DatabaseTypes';
import { 
  IWebViewSourceManager,
  WebViewSourceConfig,
  WebViewConfigFactory
} from 'manxia_source_engine/src/main/ets/Framework/WebView/WebViewImageLoader';
import { GlobalWebViewContainer, WebViewEventCallbacks } from 'manxia_source_engine/src/main/ets/Framework/WebView/WebViewContainerPage';
import { MangaSourceEngine, EngineConfig } from './MangaSourceEngine';
import { AntiCrawlerConfig } from 'manxia_source_engine/src/main/ets/Framework/WebView/MangaSourceTypes';
import { DataManager } from '../Data/DataManager';
import { WebViewDataCacheManager } from 'manxia_network/src/main/ets/Framework/Cache/WebViewDataCacheManager';
import { WebViewAuthManager } from './WebViewAuthManager';
import { UserAgentManager } from 'manxia_core/src/main/ets/Framework/Managers/UserAgentManager';
import { LegadoMangaSourceBridge } from '../Novel/LegadoMangaSourceBridge';
import { SourceIdentity } from 'manxia_source_engine/src/main/ets/Framework/Source/SourceIdentity';

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
 * MangaSourceEngine创建结果接口
 */
interface EngineCreationResult {
  /** 引擎实例 */
  engine: MangaSourceEngine;
  /** 实际图源ID */
  actualSourceId: number;
  /** 实际图源名称 */
  actualSourceName: string;
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
  
  // MangaSourceEngine缓存（key: sourceName，确保图源管理的稳定性）
  private mangaEngines: Map<string, MangaSourceEngine> = new Map();
  private mangaEngineSignatures: Map<string, string> = new Map();
  // sourceId到sourceName的映射（用于兼容旧代码）
  private sourceIdToName: Map<number, string> = new Map();
  private sourceIdToPkg: Map<number, string> = new Map();
  private sourceNameToPkg: Map<string, string> = new Map();
  private globalWebViewController: webview.WebviewController | null = null;

  /**
   * 私有构造函数
   */
  private userAgentManager: UserAgentManager;

  private constructor() {
    this.databaseManager = DatabaseManager.getInstance();
    this.dataManager = DataManager.getInstance();
    this.userAgentManager = UserAgentManager.getInstance();
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
   * @param sourceId 图源ID（字符串或数字）
   * @param sourceName 图源名称（可选，用于清理MangaSourceEngine缓存）
   */
  removeSource(sourceId: string, sourceName?: string): void {
    try {
      // 销毁WebView实例
      this.destroyWebViewInstance(sourceId);
      
      // 移除配置
      this.sourceConfigs.delete(sourceId);
      
      // 【关键】清理MangaSourceEngine缓存
      const numericId = Number(sourceId);
      if (!isNaN(numericId)) {
        this.releaseMangaEngine(numericId);
      }
      if (sourceName) {
        this.releaseMangaEngine(sourceName);
      }
      // 同时尝试从映射表中获取sourceName并清理
      const mappedName = this.sourceIdToName.get(numericId);
      if (mappedName && mappedName !== sourceName) {
        this.releaseMangaEngine(mappedName);
      }
      this.sourceIdToName.delete(numericId);
      
      logger.info(TAG, `源配置移除完成: ${sourceId}${sourceName ? ` (${sourceName})` : ''}, MangaEngine缓存已清理`);
      
    } catch (error) {
      logger.error(TAG, `移除源配置失败: ${sourceId}, 错误: ${error instanceof Error ? error.message : String(error)}`);
      throw error as Error;
    }
  }
  
  /**
   * 通过图源名称移除MangaSourceEngine缓存
   * 用于图源被删除或更新时清理旧缓存
   */
  removeEngineByName(sourceName: string): void {
    const mappedPkg = this.sourceNameToPkg.get(sourceName);
    const cacheKey = mappedPkg && mappedPkg.length > 0 ? mappedPkg : sourceName;
    if (this.mangaEngines.has(cacheKey)) {
      logger.info(TAG, `移除MangaSourceEngine缓存: "${cacheKey}"`);
      this.mangaEngines.delete(cacheKey);
      this.mangaEngineSignatures.delete(cacheKey);
    }

    // 同时清理sourceId/sourceName映射
    const entries = Array.from(this.sourceIdToName.entries());
    for (const entry of entries) {
      if (entry[1] === sourceName) {
        this.sourceIdToName.delete(entry[0]);
        this.sourceIdToPkg.delete(entry[0]);
        logger.debug(TAG, `清理sourceId映射: ${entry[0]} -> "${sourceName}"`);
      }
    }
    this.sourceNameToPkg.delete(sourceName);
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
   * 获取指定图源应使用的User-Agent
   * @param sourceId 图源ID
   * @param configUA 图源配置中的UA（可选）
   * @returns User-Agent字符串
   */
  async getUserAgentForSource(sourceId: number, configUA?: string): Promise<string> {
    return this.userAgentManager.getUserAgent(sourceId, configUA);
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
   * 【关键重构】优先使用pkg作为主键，确保图源更新/重导后的稳定性
   * @param sourceId 图源ID（数字类型，可能不稳定）
   * @param sourceName 图源名称（展示名，仅作为兼容回退）
   * @param sourcePkg 图源包名（稳定身份）
   * @returns MangaSourceEngine实例
   */
  async getMangaEngine(sourceId: number, sourceName?: string, sourcePkg?: string): Promise<MangaSourceEngine> {
    try {
      const identity = await this.resolveSourceIdentity(sourceId, sourceName, sourcePkg);
      const cacheKey = identity.pkg.length > 0 ? identity.pkg : identity.name;
      const signature = identity.signature();
      
      // 检查缓存
      if (this.mangaEngines.has(cacheKey)) {
        const cachedSignature = this.mangaEngineSignatures.get(cacheKey) || '';
        if (cachedSignature === signature) {
          logger.debug(TAG, `✅ 使用缓存的MangaSourceEngine: "${cacheKey}"`);
          return this.mangaEngines.get(cacheKey)!;
        }
        logger.info(TAG, `MangaSourceEngine配置代际变化，重建: "${cacheKey}", ${cachedSignature} -> ${signature}`);
        this.mangaEngines.delete(cacheKey);
        this.mangaEngineSignatures.delete(cacheKey);
      }
      
      // 创建新引擎
      logger.info(TAG, `🔄 创建新的MangaSourceEngine: "${cacheKey}" (sourceId=${identity.sourceId}, pkg=${identity.pkg})`);
      const result = await this.createMangaEngine(identity);
      this.mangaEngines.set(cacheKey, result.engine);
      this.mangaEngineSignatures.set(cacheKey, signature);
      this.sourceIdToName.set(result.actualSourceId, result.actualSourceName);
      if (identity.pkg.length > 0) {
        this.sourceIdToPkg.set(result.actualSourceId, identity.pkg);
        this.sourceNameToPkg.set(result.actualSourceName, identity.pkg);
      }
      
      return result.engine;
    } catch (error) {
      logger.error(TAG, `❌ 获取MangaSourceEngine失败: sourceId=${sourceId}, sourceName="${sourceName}", sourcePkg="${sourcePkg}", 错误: ${error instanceof Error ? error.message : String(error)}`);
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
      const record: ComicSourceDatabaseRecord | null = await this.dataManager.getComicSourceById(sourceId);
      if (LegadoMangaSourceBridge.getInstance().isLegadoMangaRecord(record)) {
        return false;
      }
      const config: Object | null = await this.dataManager.getSourceConfig(sourceId);
      return !!config && !!(config as Record<string, Object | undefined>)['workflows'];
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
      const sourceName: string = entry[0];
      const engine: MangaSourceEngine = entry[1];
      try {
        engine.updateWebViewController(controller);
        logger.debug(TAG, `Engine "${sourceName}" WebView已更新`);
      } catch (error) {
        logger.warn(TAG, `Engine "${sourceName}" WebView更新失败: ${String(error)}`);
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

  private async resolveSourceIdentity(sourceId: number, sourceName?: string, sourcePkg?: string): Promise<SourceIdentity> {
    let identity: SourceIdentity | null = null;
    const normalizedPkg = sourcePkg ? sourcePkg.trim() : '';
    if (normalizedPkg.length > 0) {
      identity = await this.dataManager.getSourceIdentityByPkg(normalizedPkg);
    }
    if (!identity && sourceId > 0) {
      identity = await this.dataManager.getSourceIdentityById(sourceId);
    }
    if (!identity && sourceName && sourceName.trim().length > 0) {
      identity = await this.dataManager.getSourceIdentityByName(sourceName.trim());
    }
    if (!identity && sourceId > 0 && this.sourceIdToPkg.has(sourceId)) {
      const mappedPkg = this.sourceIdToPkg.get(sourceId) || '';
      if (mappedPkg.length > 0) {
        identity = await this.dataManager.getSourceIdentityByPkg(mappedPkg);
      }
    }
    if (!identity || !identity.isValid()) {
      throw new Error(`无法解析图源稳定身份: sourceId=${sourceId}, sourceName=${sourceName || ''}, sourcePkg=${sourcePkg || ''}`);
    }
    return identity;
  }
  
  /**
   * 创建MangaSourceEngine实例
   * 【关键重构】优先使用pkg查找，确保图源管理的稳定性
   */
  private async createMangaEngine(identity: SourceIdentity): Promise<EngineCreationResult> {
    try {
      let config: Object | null = null;
      let actualSourceId: number = identity.sourceId;
      let actualSourceName: string = identity.name;

      // 【关键】优先按pkg查找（稳定的标识符）
      logger.info(TAG, `📋 优先按pkg查找图源: "${identity.pkg}"`);
      config = await this.dataManager.getSourceConfigByPkg(identity.pkg);
      if (config) {
        logger.info(TAG, `✅ 按pkg找到图源: "${identity.pkg}", ID=${actualSourceId}`);
      } else {
        logger.warn(TAG, `⚠️ 按pkg未找到图源 "${identity.pkg}"，尝试按ID查找: ${identity.sourceId}`);
        config = await this.dataManager.getSourceConfig(identity.sourceId);
        if (config) {
          actualSourceId = identity.sourceId;
          const sourceRecord = await this.dataManager.getComicSourceById(identity.sourceId);
          if (sourceRecord && sourceRecord.name) {
            actualSourceName = sourceRecord.name;
            logger.info(TAG, `✅ 按ID找到图源: ${identity.sourceId}, 实际名称="${actualSourceName}"`);
          }
        }
      }
      
      if (!config) {
        throw new Error(`图源配置不存在: ID=${identity.sourceId}, pkg="${identity.pkg}", 名称="${identity.name}"`);
      }

      const actualSourceRecord: ComicSourceDatabaseRecord | null = await this.dataManager.getComicSourceById(actualSourceId);
      if (LegadoMangaSourceBridge.getInstance().isLegadoMangaRecord(actualSourceRecord)) {
        throw new Error(`Legado IMAGE 虚拟图源不应创建 WebView 引擎: ID=${actualSourceId}, 名称="${actualSourceName}"`);
      }
      
      // 检查是否为WebView类型
      if (!(!!config && !!(config as Record<string, Object | undefined>)['workflows'])) {
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
      
      logger.info(TAG, `✅ MangaSourceEngine创建成功: "${actualSourceName}" (ID=${actualSourceId}, pkg=${identity.pkg})`);
      const result: EngineCreationResult = {engine, actualSourceId, actualSourceName};
      return result;
      
    } catch (error) {
      logger.error(TAG, `创建MangaSourceEngine失败: ${identity.sourceId}, pkg=${identity.pkg}, 错误: ${error instanceof Error ? error.message : String(error)}`);
      throw error as Error;
    }
  }
  
  /**
   * 释放MangaSourceEngine实例
   * 【重构】支持按pkg、sourceName或sourceId释放
   */
  releaseMangaEngine(sourceIdOrName: number | string): void {
    if (typeof sourceIdOrName === 'string') {
      const mappedPkg = this.sourceNameToPkg.get(sourceIdOrName);
      const cacheKey = mappedPkg && mappedPkg.length > 0 ? mappedPkg : sourceIdOrName;
      if (this.mangaEngines.has(cacheKey)) {
        logger.info(TAG, `释放MangaSourceEngine: "${cacheKey}"`);
        this.mangaEngines.delete(cacheKey);
        this.mangaEngineSignatures.delete(cacheKey);
      }
    } else {
      const sourcePkg = this.sourceIdToPkg.get(sourceIdOrName);
      const sourceName = this.sourceIdToName.get(sourceIdOrName);
      const cacheKey = sourcePkg && sourcePkg.length > 0 ? sourcePkg : (sourceName || '');
      if (cacheKey.length > 0 && this.mangaEngines.has(cacheKey)) {
        logger.info(TAG, `释放MangaSourceEngine: ${sourceIdOrName} -> "${cacheKey}"`);
        this.mangaEngines.delete(cacheKey);
        this.mangaEngineSignatures.delete(cacheKey);
      }
      this.sourceIdToName.delete(sourceIdOrName);
      this.sourceIdToPkg.delete(sourceIdOrName);
    }
  }

  /**
   * 图源运行配置已变化时清理内存状态。
   * 用于镜像站点、domain/apiDomain 等会影响工作流变量的设置变更。
   */
  invalidateSourceRuntime(sourceId: number, sourceName?: string, sourcePkg?: string): void {
    try {
      const sourceIdText: string = String(sourceId);
      this.destroyWebViewInstance(sourceIdText);
      this.sourceConfigs.delete(sourceIdText);
      WebViewDataCacheManager.getInstance().clearSource(sourceId);

      const mappedName: string | undefined = this.sourceIdToName.get(sourceId);
      const mappedPkg: string | undefined = this.sourceIdToPkg.get(sourceId);
      const cacheKeys: string[] = [];
      if (sourcePkg && sourcePkg.length > 0) {
        cacheKeys.push(sourcePkg);
      }
      if (mappedPkg && mappedPkg.length > 0) {
        cacheKeys.push(mappedPkg);
      }
      if (mappedName && mappedName.length > 0) {
        cacheKeys.push(mappedName);
      }
      if (sourceName && sourceName.length > 0) {
        cacheKeys.push(sourceName);
      }
      for (let index = 0; index < cacheKeys.length; index++) {
        const cacheKey = cacheKeys[index];
        if (this.mangaEngines.has(cacheKey)) {
          this.mangaEngines.delete(cacheKey);
          this.mangaEngineSignatures.delete(cacheKey);
          logger.info(TAG, `已清理图源运行缓存: "${cacheKey}"`);
        }
      }
      this.sourceIdToName.delete(sourceId);
      this.sourceIdToPkg.delete(sourceId);
      if (sourceName) {
        this.sourceNameToPkg.delete(sourceName);
      }
    } catch (error) {
      logger.warn(TAG, `清理图源运行缓存失败: sourceId=${sourceId}, sourceName=${sourceName || ''}, sourcePkg=${sourcePkg || ''}, error=${String(error)}`);
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
