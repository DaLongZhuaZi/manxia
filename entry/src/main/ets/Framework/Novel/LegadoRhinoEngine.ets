/**
 * Legado Rhino引擎集成层
 * 
 * 提供统一的JS执行接口，自动选择最佳执行引擎：
 * 1. Rhino WASM沙箱（CheerpJ模式）- 完全兼容Android Legado
 * 2. Rhino WASM沙箱（离线模式）- 纯JS实现，兼容性好
 * 3. Native JSVM引擎 - 性能最佳，但兼容性有限
 * 4. WebView引擎 - 降级方案
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/LegadoRhinoEngine.ets
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getRhinoWasmExecutor, RhinoWasmExecutor, RhinoContext, RhinoExecuteResult } from './RhinoWasmExecutor';
import { LegadoJsEngine, JsContext, JsExecuteResult } from './LegadoJsEngine';
import { webview } from '@kit.ArkWeb';

const TAG = 'LegadoRhinoEngine';

/**
 * 执行引擎类型
 */
export enum JsEngineType {
  /** Rhino WASM沙箱（CheerpJ模式） */
  RHINO_CHEERPJ = 'rhino_cheerpj',
  /** Rhino WASM沙箱（离线模式） */
  RHINO_OFFLINE = 'rhino_offline',
  /** Native JSVM引擎 */
  NATIVE_JSVM = 'native_jsvm',
  /** WebView引擎 */
  WEBVIEW = 'webview',
  /** 自动选择 */
  AUTO = 'auto'
}

/**
 * 引擎配置
 */
export interface EngineConfig {
  /** 首选引擎类型 */
  preferredEngine: JsEngineType;
  /** 是否启用Rhino沙箱 */
  enableRhinoSandbox: boolean;
  /** Rhino沙箱初始化超时（毫秒） */
  rhinoInitTimeout: number;
  /** 脚本执行超时（毫秒） */
  executeTimeout: number;
  /** 是否启用引擎降级 */
  enableFallback: boolean;
}

/**
 * 引擎状态接口
 */
export interface EngineStatus {
  initialized: boolean;
  currentEngine: JsEngineType;
  rhinoReady: boolean;
  legadoEngineAvailable: boolean;
  rhinoSandboxMode: string;
}

/**
 * 默认配置
 */
const DEFAULT_CONFIG: EngineConfig = {
  preferredEngine: JsEngineType.AUTO,
  enableRhinoSandbox: true,
  rhinoInitTimeout: 30000,
  executeTimeout: 30000,
  enableFallback: true
};

/**
 * Legado Rhino引擎
 * 统一管理多种JS执行引擎
 */
export class LegadoRhinoEngine {
  private static instance: LegadoRhinoEngine | null = null;
  
  private config: EngineConfig = DEFAULT_CONFIG;
  private rhinoExecutor: RhinoWasmExecutor | null = null;
  private legadoEngine: LegadoJsEngine | null = null;
  private currentEngineType: JsEngineType = JsEngineType.AUTO;
  private isInitialized: boolean = false;
  private initPromise: Promise<boolean> | null = null;
  
  private constructor() {}
  
  /**
   * 获取单例实例
   */
  static getInstance(): LegadoRhinoEngine {
    if (!LegadoRhinoEngine.instance) {
      LegadoRhinoEngine.instance = new LegadoRhinoEngine();
    }
    return LegadoRhinoEngine.instance;
  }
  
  /**
   * 设置配置
   */
  setConfig(config: Partial<EngineConfig>): void {
    // ArkTS不支持spread操作符，手动合并配置
    if (config.preferredEngine !== undefined) {
      this.config.preferredEngine = config.preferredEngine;
    }
    if (config.enableRhinoSandbox !== undefined) {
      this.config.enableRhinoSandbox = config.enableRhinoSandbox;
    }
    if (config.rhinoInitTimeout !== undefined) {
      this.config.rhinoInitTimeout = config.rhinoInitTimeout;
    }
    if (config.executeTimeout !== undefined) {
      this.config.executeTimeout = config.executeTimeout;
    }
    if (config.enableFallback !== undefined) {
      this.config.enableFallback = config.enableFallback;
    }
    logger.info(TAG, `配置已更新: ${JSON.stringify(this.config)}`);
  }
  
  /**
   * 设置WebView控制器（用于LegadoJsEngine的降级执行）
   * 注意：Rhino沙箱需要独立的WebView，使用setRhinoWebviewController设置
   */
  setWebviewController(controller: webview.WebviewController): void {
    logger.info(TAG, '设置WebView控制器（用于LegadoJsEngine）...');
    
    // 传递给LegadoJsEngine作为降级方案
    if (!this.legadoEngine) {
      this.legadoEngine = LegadoJsEngine.getInstance();
    }
    this.legadoEngine.setWebviewController(controller);
    logger.info(TAG, 'WebView控制器已设置到LegadoJsEngine');
  }
  
  /**
   * 设置Rhino沙箱专用的WebView控制器
   * Rhino沙箱需要独立的WebView实例来运行沙箱脚本
   */
  setRhinoWebviewController(controller: webview.WebviewController): void {
    logger.info(TAG, '设置Rhino沙箱WebView控制器...');
    
    // 如果引擎还未初始化，先创建执行器
    if (!this.rhinoExecutor) {
      this.rhinoExecutor = getRhinoWasmExecutor();
      logger.info(TAG, '创建了新的RhinoWasmExecutor');
    }
    
    // 传递给RhinoWasmExecutor
    this.rhinoExecutor.setWebviewController(controller);
    logger.info(TAG, 'WebView控制器已设置到RhinoWasmExecutor');
    
    // 尝试初始化Rhino沙箱（异步，不阻塞）
    this.tryInitializeRhinoSandbox();
  }
  
  /**
   * 尝试初始化Rhino沙箱
   */
  private async tryInitializeRhinoSandbox(): Promise<void> {
    if (!this.rhinoExecutor) {
      return;
    }
    
    try {
      logger.info(TAG, '尝试初始化Rhino WASM沙箱...');
      const ready = await this.rhinoExecutor.initialize();
      
      if (ready && this.rhinoExecutor.isSandboxReady()) {
        this.currentEngineType = JsEngineType.RHINO_OFFLINE;
        this.isInitialized = true;
        logger.info(TAG, 'Rhino WASM沙箱初始化成功，将使用沙箱执行');
      } else {
        logger.warn(TAG, 'Rhino WASM沙箱初始化失败，将使用降级引擎');
        this.currentEngineType = JsEngineType.NATIVE_JSVM;
        this.isInitialized = true;
      }
    } catch (error) {
      logger.error(TAG, `Rhino沙箱初始化异常: ${String(error)}`);
      this.currentEngineType = JsEngineType.NATIVE_JSVM;
      this.isInitialized = true;
    }
  }
  
  /**
   * 设置jsLib（书源的JS库）
   */
  setJsLib(jsLib: string): void {
    if (this.legadoEngine) {
      this.legadoEngine.setJsLib(jsLib);
    }
    // Rhino沙箱的jsLib会随执行上下文注入，这里只同步降级引擎的库内容。
    logger.debug(TAG, `已设置jsLib (${jsLib.length}字符)`);
  }
  
  /**
   * 获取当前配置
   */
  getConfig(): EngineConfig {
    // ArkTS不支持spread操作符，手动复制
    const copy: EngineConfig = {
      preferredEngine: this.config.preferredEngine,
      enableRhinoSandbox: this.config.enableRhinoSandbox,
      rhinoInitTimeout: this.config.rhinoInitTimeout,
      executeTimeout: this.config.executeTimeout,
      enableFallback: this.config.enableFallback
    };
    return copy;
  }
  
  /**
   * 初始化引擎
   */
  async initialize(): Promise<boolean> {
    if (this.isInitialized) {
      return true;
    }
    
    if (this.initPromise) {
      return this.initPromise;
    }
    
    this.initPromise = this.doInitialize();
    return this.initPromise;
  }
  
  private async doInitialize(): Promise<boolean> {
    logger.info(TAG, '开始初始化Legado Rhino引擎...');
    
    try {
      // 首先确保LegadoJsEngine可用（作为主要引擎或降级方案）
      if (!this.legadoEngine) {
        this.legadoEngine = LegadoJsEngine.getInstance();
      }
      
      // 检查Rhino WASM沙箱是否已经就绪
      if (this.config.enableRhinoSandbox && this.rhinoExecutor) {
        // 如果沙箱已就绪，直接使用
        if (this.rhinoExecutor.isSandboxReady()) {
          this.currentEngineType = JsEngineType.RHINO_OFFLINE;
          logger.info(TAG, 'Rhino WASM沙箱已就绪');
          this.isInitialized = true;
          return true;
        }
        
        // 如果沙箱正在初始化，等待一段时间
        logger.info(TAG, '等待Rhino沙箱初始化完成...');
        const maxWaitTime = 5000; // 最多等待5秒
        const checkInterval = 200; // 每200ms检查一次
        let waited = 0;
        
        while (waited < maxWaitTime) {
          await this.sleep(checkInterval);
          waited += checkInterval;
          
          if (this.rhinoExecutor.isSandboxReady()) {
            this.currentEngineType = JsEngineType.RHINO_OFFLINE;
            logger.info(TAG, `Rhino WASM沙箱初始化成功（等待了${waited}ms）`);
            this.isInitialized = true;
            return true;
          }
        }
        
        logger.warn(TAG, `Rhino沙箱初始化超时（等待了${waited}ms），使用降级引擎`);
      }
      
      // 如果沙箱未就绪或未启用，使用LegadoJsEngine
      this.currentEngineType = JsEngineType.NATIVE_JSVM;
      logger.info(TAG, '使用NativeJsEngine模式（沙箱未就绪或未启用）');
      this.isInitialized = true;
      return true;
      
    } catch (error) {
      logger.error(TAG, `引擎初始化异常: ${String(error)}`);
      
      // 尝试降级
      if (this.config.enableFallback) {
        if (!this.legadoEngine) {
          this.legadoEngine = LegadoJsEngine.getInstance();
        }
        this.currentEngineType = JsEngineType.NATIVE_JSVM;
        logger.info(TAG, '异常后使用NativeJsEngine模式');
        this.isInitialized = true;
        return true;
      }
      
      return false;
    }
  }
  
  /**
   * 辅助方法：睡眠
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
  
  /**
   * 执行JavaScript代码
   * 
   * @param code JavaScript代码
   * @param context 执行上下文
   * @returns 执行结果
   */
  async execute(code: string, context: JsContext = {}): Promise<JsExecuteResult> {
    if (!code || code.trim() === '') {
      return { success: true, result: '' };
    }
    
    // 确保引擎已初始化
    if (!this.isInitialized) {
      const initialized = await this.initialize();
      if (!initialized) {
        return {
          success: false,
          result: '',
          error: '引擎初始化失败'
        };
      }
    }
    
    // 检测代码是否需要网络请求
    // 如果包含网络请求函数，必须使用LegadoJsEngine（WebView）执行
    // 因为Rhino沙箱无法发起真正的网络请求
    const needsNetwork = this.codeNeedsNetwork(code);
    
    // 根据当前引擎类型执行
    try {
      // 如果代码需要网络请求，优先使用LegadoJsEngine（WebView）
      // WebView支持XMLHttpRequest同步模式，可以正确执行网络请求
      if (needsNetwork && this.legadoEngine) {
        logger.debug(TAG, '代码包含网络请求函数，使用WebView执行');
        return await this.legadoEngine.execute(code, context);
      }
      
      // 不需要网络请求的代码，可以使用Rhino沙箱执行
      if (this.rhinoExecutor && this.rhinoExecutor.isSandboxReady()) {
        return await this.executeInRhino(code, context);
      } else if (this.legadoEngine) {
        return await this.legadoEngine.execute(code, context);
      } else {
        return {
          success: false,
          result: '',
          error: '没有可用的执行引擎'
        };
      }
    } catch (error) {
      // 执行失败，尝试降级
      if (this.config.enableFallback && this.legadoEngine) {
        logger.warn(TAG, `Rhino执行失败，降级到WebView: ${String(error)}`);
        return await this.legadoEngine.execute(code, context);
      }
      
      return {
        success: false,
        result: '',
        error: String(error)
      };
    }
  }
  
  /**
   * 检测代码是否需要网络请求
   * 包含以下函数调用时需要使用WebView执行：
   * - java.ajax / java.ajaxAll - 网络请求
   * - java.post / java.get(url) - 网络请求
   * - java.connect / java.head - 网络请求
   * - java.startBrowserAwait / java.startBrowser - 浏览器操作
   * - java.webView - WebView操作
   * - Jsoup.connect - 网络请求
   */
  private codeNeedsNetwork(code: string): boolean {
    // 明确需要网络请求的函数模式
    const networkPatterns: RegExp[] = [
      /java\s*\.\s*ajax\s*\(/,
      /java\s*\.\s*ajaxAll\s*\(/,
      /java\s*\.\s*post\s*\(/,
      /java\s*\.\s*connect\s*\(/,
      /java\s*\.\s*head\s*\(/,
      /java\s*\.\s*startBrowserAwait\s*\(/,
      /java\s*\.\s*startBrowser\s*\(/,
      /java\s*\.\s*webView\s*\(/,
      /java\s*\.\s*cacheFile\s*\(/,
      /java\s*\.\s*importScript\s*\(/,
      /Jsoup\s*\.\s*connect\s*\(/
    ];
    
    for (const pattern of networkPatterns) {
      if (pattern.test(code)) {
        return true;
      }
    }
    
    // java.get 需要特殊处理：
    // - java.get("key") / java.get("page") / java.get("result") / java.get("baseUrl") 是变量获取，不需要网络
    // - java.get(url) 或 java.get("http...") 是网络请求，需要WebView
    if (code.includes('java.get')) {
      // 检查是否只是变量获取
      const varGetPattern = /java\.get\s*\(\s*["'](key|page|result|baseUrl|sourceUrl)["']\s*\)/g;
      const allGetPattern = /java\.get\s*\(/g;
      const varGetMatches = code.match(varGetPattern) || [];
      const allGetMatches = code.match(allGetPattern) || [];
      // 如果所有java.get调用都是变量获取，则不需要网络
      if (varGetMatches.length < allGetMatches.length) {
        return true; // 有非变量获取的java.get调用，需要网络
      }
    }
    
    return false;
  }
  
  /**
   * 在Rhino沙箱中执行
   */
  private async executeInRhino(code: string, context: JsContext): Promise<JsExecuteResult> {
    if (!this.rhinoExecutor) {
      throw new Error('Rhino执行器未初始化');
    }
    
    // 转换上下文格式
    const rhinoContext: RhinoContext = {
      result: context.result,
      baseUrl: context.baseUrl,
      sourceUrl: context.variables?.['sourceUrl'] || context.baseUrl,
      key: context.key,
      page: context.page,
      book: context.book,
      chapter: context.chapter,
      variables: context.variables
    };
    
    if (context.variables) {
      rhinoContext.sourceVariable = context.variables['__sourceVariable'] || '';
      rhinoContext.loginInfo = context.variables['__loginInfo'] || '';
      rhinoContext.loginHeader = context.variables['__loginHeader'] || '';
    }
    
    const result = await this.rhinoExecutor.execute(code, rhinoContext, this.config.executeTimeout);
    
    return {
      success: result.success,
      result: result.result,
      error: result.error
    };
  }
  
  /**
   * 获取当前引擎类型
   */
  getCurrentEngineType(): JsEngineType {
    return this.currentEngineType;
  }
  
  /**
   * 检查引擎是否就绪
   */
  isReady(): boolean {
    return this.isInitialized;
  }
  
  /**
   * 获取引擎状态信息
   */
  getStatus(): EngineStatus {
    const status: EngineStatus = {
      initialized: this.isInitialized,
      currentEngine: this.currentEngineType,
      rhinoReady: this.rhinoExecutor !== null ? this.rhinoExecutor.isSandboxReady() : false,
      legadoEngineAvailable: this.legadoEngine !== null,
      rhinoSandboxMode: 'offline'
    };
    return status;
  }
  
  /**
   * 销毁引擎
   */
  destroy(): void {
    if (this.rhinoExecutor) {
      this.rhinoExecutor.destroy();
      this.rhinoExecutor = null;
    }

    if (this.legadoEngine) {
      this.legadoEngine.reset();
      this.legadoEngine = null;
    }
    this.isInitialized = false;
    this.initPromise = null;
    this.currentEngineType = JsEngineType.AUTO;
    
    LegadoRhinoEngine.instance = null;
    
    logger.info(TAG, 'Legado Rhino引擎已销毁');
  }
  
  /**
   * 超时Promise
   */
  private timeout(ms: number): Promise<boolean> {
    return new Promise((resolve) => {
      setTimeout(() => resolve(false), ms);
    });
  }
}

/**
 * 获取Legado Rhino引擎实例
 */
export function getLegadoRhinoEngine(): LegadoRhinoEngine {
  return LegadoRhinoEngine.getInstance();
}

/**
 * 快速执行Rhino脚本
 * 使用统一的引擎管理器执行
 */
export async function executeRhinoJs(code: string, context?: JsContext): Promise<JsExecuteResult> {
  const engine = getLegadoRhinoEngine();
  return engine.execute(code, context);
}
