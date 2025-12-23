/**
 * NativeJsEngine - 基于JSVM-API的原生JavaScript执行引擎
 * 
 * 使用HarmonyOS NEXT的JSVM-API实现，无需JIT权限，使用解释器模式执行
 * 性能优于WebView方案，适用于执行Legado书源的JS规则
 * 
 * 注意：需要在build-profile.json5中配置Native编译才能使用
 */

import jsvmEngineModule from 'libjsvm_engine.so';
import { logger } from '../../Utils/Logger';

const TAG = 'NativeJsEngine';

/**
 * Native模块接口定义
 */
interface JsExecuteResult {
  success: boolean;
  result: string;
}

interface JsvmEngineInterface {
  createVm(): number;
  destroyVm(vmId: number): void;
  executeJs(vmId: number, jsCode: string): JsExecuteResult;
  setGlobalString(vmId: number, name: string, value: string): boolean;
  setGlobalNumber(vmId: number, name: string, value: number): boolean;
  getVmCount(): number;
}

// 检查Native模块是否正确加载
let jsvmEngine: JsvmEngineInterface | null = null;
let nativeModuleLoadError: string = '';

try {
  if (jsvmEngineModule && typeof jsvmEngineModule.createVm === 'function') {
    jsvmEngine = jsvmEngineModule as JsvmEngineInterface;
    logger.info(TAG, 'Native JSVM模块加载成功');
  } else {
    nativeModuleLoadError = 'Native模块加载成功但接口不完整';
    logger.warn(TAG, nativeModuleLoadError);
  }
} catch (e) {
  nativeModuleLoadError = `Native模块加载失败: ${String(e)}`;
  logger.warn(TAG, `${nativeModuleLoadError}，将使用降级方案`);
}


/**
 * JS执行结果接口
 */
export interface JsResult {
  success: boolean;
  result: string;
  error?: string;
}

/**
 * JS执行上下文
 */
export interface JsContext {
  /** 上一步的结果 */
  result?: string;
  /** 基础URL */
  baseUrl?: string;
  /** 搜索关键字 */
  key?: string;
  /** 页码 */
  page?: number;
  /** 书源URL */
  sourceUrl?: string;
  /** 自定义变量 */
  variables?: Record<string, string>;
}

/**
 * 原生JS引擎类
 */
export class NativeJsEngine {
  private vmId: number = -1;
  private isInitialized: boolean = false;
  
  /**
   * 检查Native模块是否可用
   */
  static isNativeModuleAvailable(): boolean {
    return jsvmEngine !== null;
  }
  
  /**
   * 获取Native模块加载错误信息
   */
  static getNativeModuleError(): string {
    return nativeModuleLoadError;
  }
  
  /**
   * 初始化引擎
   */
  async initialize(): Promise<boolean> {
    if (this.isInitialized) {
      return true;
    }
    
    // 检查Native模块是否可用
    if (!jsvmEngine) {
      logger.error(TAG, `Native模块不可用: ${nativeModuleLoadError}`);
      return false;
    }
    
    try {
      this.vmId = jsvmEngine.createVm();
      if (this.vmId < 0) {
        logger.error(TAG, '创建JSVM实例失败');
        return false;
      }
      
      this.isInitialized = true;
      logger.info(TAG, `JSVM实例创建成功，vmId=${this.vmId}`);
      
      // 注入基础工具函数
      await this.injectHelperFunctions();
      
      return true;
    } catch (e) {
      logger.error(TAG, `初始化JSVM失败: ${String(e)}`);
      return false;
    }
  }
  
  /**
   * 销毁引擎
   */
  destroy(): void {
    if (this.vmId >= 0 && jsvmEngine) {
      try {
        jsvmEngine.destroyVm(this.vmId);
        logger.info(TAG, `JSVM实例已销毁，vmId=${this.vmId}`);
      } catch (e) {
        logger.error(TAG, `销毁JSVM失败: ${String(e)}`);
      }
      this.vmId = -1;
      this.isInitialized = false;
    }
  }
  
  /**
   * 执行JavaScript代码
   * @param code JavaScript代码
   * @param context 执行上下文
   * @returns 执行结果
   */
  async execute(code: string, context?: JsContext): Promise<JsResult> {
    // 检查Native模块是否可用
    if (!jsvmEngine) {
      return { 
        success: false, 
        result: '', 
        error: `Native JSVM模块未加载。${nativeModuleLoadError}\n\n请在build-profile.json5中配置Native编译选项。` 
      };
    }
    
    if (!this.isInitialized) {
      const initialized = await this.initialize();
      if (!initialized) {
        return { success: false, result: '', error: 'JSVM初始化失败' };
      }
    }
    
    try {
      // 设置上下文变量
      if (context) {
        await this.setContext(context);
      }
      
      // 执行代码
      const result = jsvmEngine.executeJs(this.vmId, code);
      
      if (result.success) {
        logger.debug(TAG, `JS执行成功: ${result.result.substring(0, 100)}`);
        return { success: true, result: result.result };
      } else {
        logger.warn(TAG, `JS执行失败: ${result.result}`);
        return { success: false, result: '', error: result.result };
      }
    } catch (e) {
      const errorMsg = String(e);
      logger.error(TAG, `JS执行异常: ${errorMsg}`);
      return { success: false, result: '', error: errorMsg };
    }
  }
  
  /**
   * 执行JavaScript代码并返回字符串结果
   * @param code JavaScript代码
   * @param context 执行上下文
   * @returns 结果字符串，失败返回空字符串
   */
  async executeForString(code: string, context?: JsContext): Promise<string> {
    const result = await this.execute(code, context);
    return result.success ? result.result : '';
  }
  
  /**
   * 设置执行上下文
   */
  private async setContext(context: JsContext): Promise<void> {
    if (!jsvmEngine) {
      return;
    }
    if (context.result !== undefined) {
      jsvmEngine.setGlobalString(this.vmId, 'result', context.result);
    }
    if (context.baseUrl !== undefined) {
      jsvmEngine.setGlobalString(this.vmId, 'baseUrl', context.baseUrl);
    }
    if (context.key !== undefined) {
      jsvmEngine.setGlobalString(this.vmId, 'key', context.key);
    }
    if (context.page !== undefined) {
      jsvmEngine.setGlobalNumber(this.vmId, 'page', context.page);
    }
    if (context.sourceUrl !== undefined) {
      jsvmEngine.setGlobalString(this.vmId, 'sourceUrl', context.sourceUrl);
    }
    
    // 设置自定义变量
    if (context.variables) {
      const keys = Object.keys(context.variables);
      for (let i = 0; i < keys.length; i++) {
        const varName = keys[i];
        const varValue = context.variables[varName];
        jsvmEngine.setGlobalString(this.vmId, varName, varValue);
      }
    }
  }
  
  /**
   * 注入基础工具函数
   */
  private async injectHelperFunctions(): Promise<void> {
    // 注入encodeURI和encodeURIComponent（JSVM应该已内置，但确保可用）
    // 注入一些Legado常用的java对象模拟
    const helperCode = `
      // 模拟Legado的java对象
      var java = {
        // 字符串操作
        getString: function(path) {
          // 简单实现，实际需要根据path从result中提取
          return '';
        },
        // 时间格式化
        timeFormat: function(timestamp) {
          var d = new Date(timestamp);
          return d.getFullYear() + '/' + 
                 String(d.getMonth() + 1).padStart(2, '0') + '/' + 
                 String(d.getDate()).padStart(2, '0') + ' ' +
                 String(d.getHours()).padStart(2, '0') + ':' +
                 String(d.getMinutes()).padStart(2, '0');
        },
        // 日志
        log: function(msg) {
          // 在Native环境中无法直接打印，忽略
        },
        // 变量存储
        _vars: {},
        put: function(varName, value) {
          this._vars[varName] = value;
          // 同时更新全局变量
          if (varName === 'key') { key = value; }
          if (varName === 'page') { page = value; }
          if (varName === 'result') { result = value; }
        },
        get: function(varName) {
          // 优先从全局变量获取
          if (varName === 'key') return typeof key !== 'undefined' ? key : '';
          if (varName === 'page') return typeof page !== 'undefined' ? page : 1;
          if (varName === 'result') return typeof result !== 'undefined' ? result : '';
          if (varName === 'baseUrl') return typeof baseUrl !== 'undefined' ? baseUrl : '';
          if (varName === 'sourceUrl') return typeof sourceUrl !== 'undefined' ? sourceUrl : '';
          // 其次从_vars获取
          return this._vars[varName] || '';
        },
        // Base64
        base64Decode: function(str) {
          try {
            // 使用atob（如果可用）
            if (typeof atob === 'function') {
              return atob(str);
            }
            // 简单的Base64解码实现
            var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
            var output = '';
            var i = 0;
            str = str.replace(/[^A-Za-z0-9\\+\\/\\=]/g, '');
            while (i < str.length) {
              var enc1 = chars.indexOf(str.charAt(i++));
              var enc2 = chars.indexOf(str.charAt(i++));
              var enc3 = chars.indexOf(str.charAt(i++));
              var enc4 = chars.indexOf(str.charAt(i++));
              var chr1 = (enc1 << 2) | (enc2 >> 4);
              var chr2 = ((enc2 & 15) << 4) | (enc3 >> 2);
              var chr3 = ((enc3 & 3) << 6) | enc4;
              output += String.fromCharCode(chr1);
              if (enc3 !== 64) output += String.fromCharCode(chr2);
              if (enc4 !== 64) output += String.fromCharCode(chr3);
            }
            return output;
          } catch (e) {
            return '';
          }
        },
        base64Encode: function(str) {
          try {
            if (typeof btoa === 'function') {
              return btoa(str);
            }
            var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
            var output = '';
            var i = 0;
            while (i < str.length) {
              var chr1 = str.charCodeAt(i++);
              var chr2 = str.charCodeAt(i++);
              var chr3 = str.charCodeAt(i++);
              var enc1 = chr1 >> 2;
              var enc2 = ((chr1 & 3) << 4) | (chr2 >> 4);
              var enc3 = ((chr2 & 15) << 2) | (chr3 >> 6);
              var enc4 = chr3 & 63;
              if (isNaN(chr2)) {
                enc3 = enc4 = 64;
              } else if (isNaN(chr3)) {
                enc4 = 64;
              }
              output += chars.charAt(enc1) + chars.charAt(enc2) + chars.charAt(enc3) + chars.charAt(enc4);
            }
            return output;
          } catch (e) {
            return '';
          }
        }
      };
      
      // 模拟cookie对象
      var cookie = {
        _cookies: {},
        getCookie: function(url) {
          return this._cookies[url] || '';
        },
        setCookie: function(url, value) {
          this._cookies[url] = value;
        },
        removeCookie: function(url) {
          delete this._cookies[url];
        }
      };
      
      // 模拟source对象
      var source = {
        _key: typeof sourceUrl !== 'undefined' ? sourceUrl : '',
        getKey: function() {
          return this._key;
        }
      };
      
      // 确保encodeURIComponent可用
      if (typeof encodeURIComponent === 'undefined') {
        var encodeURIComponent = function(str) {
          return str; // 降级处理
        };
      }
      
      // 确保encodeURI可用
      if (typeof encodeURI === 'undefined') {
        var encodeURI = function(str) {
          return str; // 降级处理
        };
      }
      
      true; // 返回true表示初始化成功
    `;
    
    if (!jsvmEngine) {
      logger.warn(TAG, '注入辅助函数失败: Native模块未加载');
      return;
    }
    const result = jsvmEngine.executeJs(this.vmId, helperCode);
    if (!result.success) {
      logger.warn(TAG, `注入辅助函数失败: ${result.result}`);
    } else {
      logger.debug(TAG, '辅助函数注入成功');
    }
  }
  
  /**
   * 获取当前活跃的虚拟机数量
   */
  static getVmCount(): number {
    if (!jsvmEngine) {
      return 0;
    }
    try {
      return jsvmEngine.getVmCount();
    } catch (e) {
      return 0;
    }
  }
  
  /**
   * 检查引擎是否已初始化
   */
  isReady(): boolean {
    return this.isInitialized && this.vmId >= 0;
  }
}

// 全局单例引擎实例
let globalEngine: NativeJsEngine | null = null;

/**
 * 获取全局JS引擎实例
 */
export function getNativeJsEngine(): NativeJsEngine {
  if (!globalEngine) {
    globalEngine = new NativeJsEngine();
  }
  return globalEngine;
}

/**
 * 销毁全局JS引擎实例
 */
export function destroyNativeJsEngine(): void {
  if (globalEngine) {
    globalEngine.destroy();
    globalEngine = null;
  }
}

/**
 * 快速执行JS代码（使用全局引擎）
 */
export async function executeJs(code: string, context?: JsContext): Promise<JsResult> {
  const engine = getNativeJsEngine();
  return engine.execute(code, context);
}

/**
 * 快速执行JS代码并返回字符串（使用全局引擎）
 */
export async function executeJsForString(code: string, context?: JsContext): Promise<string> {
  const engine = getNativeJsEngine();
  return engine.executeForString(code, context);
}
