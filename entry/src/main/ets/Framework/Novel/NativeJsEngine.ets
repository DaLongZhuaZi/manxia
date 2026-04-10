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
  private initPromise: Promise<boolean> | null = null;
  // Serialize setContext + executeJs for a single VM instance.
  private executeSequence: Promise<void> = Promise.resolve();
  
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
      this.initPromise = null;
      this.executeSequence = Promise.resolve();
    }
  }

  private async ensureInitialized(): Promise<boolean> {
    if (this.isInitialized) {
      return true;
    }

    if (!this.initPromise) {
      this.initPromise = this.initialize().then((initialized: boolean): boolean => {
        this.initPromise = null;
        return initialized;
      }).catch((error: Object): boolean => {
        this.initPromise = null;
        logger.error(TAG, `初始化流程异常: ${String(error)}`);
        return false;
      });
    }

    return await this.initPromise;
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
      const initialized = await this.ensureInitialized();
      if (!initialized) {
        return { success: false, result: '', error: 'JSVM初始化失败' };
      }
    }

    return await this.executeWithLock(code, context);
  }

  private async executeWithLock(code: string, context?: JsContext): Promise<JsResult> {
    const runTask = this.executeSequence.then(async (): Promise<JsResult> => {
      try {
        const engine = jsvmEngine;
        if (!engine) {
          return {
            success: false,
            result: '',
            error: `Native JSVM模块未加载。${nativeModuleLoadError}\n\n请在build-profile.json5中配置Native编译选项。`
          };
        }

        if (context) {
          this.setContext(context);
        }

        const result = engine.executeJs(this.vmId, code);

        if (result.success) {
          logger.debug(TAG, `JS执行成功: ${result.result.substring(0, 100)}`);
          return { success: true, result: result.result };
        }

        logger.warn(TAG, `JS执行失败: ${result.result}`);
        return { success: false, result: '', error: result.result };
      } catch (e) {
        const errorMsg = String(e);
        logger.error(TAG, `JS执行异常: ${errorMsg}`);
        return { success: false, result: '', error: errorMsg };
      }
    });

    this.executeSequence = runTask.then((): void => {}, (): void => {});
    return await runTask;
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
  private setContext(context: JsContext): void {
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
        // Base64 - 纯JavaScript实现，不依赖atob/btoa
        base64Decode: function(str) {
          if (!str) return '';
          var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
          var output = '';
          str = String(str).replace(/[^A-Za-z0-9+/=]/g, '');
          var i = 0;
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
        },
        base64Encode: function(str) {
          if (!str) return '';
          var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
          var output = '';
          str = String(str);
          var i = 0;
          while (i < str.length) {
            var chr1 = str.charCodeAt(i++);
            var chr2 = i < str.length ? str.charCodeAt(i++) : NaN;
            var chr3 = i < str.length ? str.charCodeAt(i++) : NaN;
            var enc1 = chr1 >> 2;
            var enc2 = ((chr1 & 3) << 4) | (isNaN(chr2) ? 0 : (chr2 >> 4));
            var enc3 = isNaN(chr2) ? 64 : (((chr2 & 15) << 2) | (isNaN(chr3) ? 0 : (chr3 >> 6)));
            var enc4 = isNaN(chr3) ? 64 : (chr3 & 63);
            output += chars.charAt(enc1) + chars.charAt(enc2) + chars.charAt(enc3) + chars.charAt(enc4);
          }
          return output;
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
        _vars: {},
        getKey: function() {
          return this._key;
        },
        setVariable: function(name, value) {
          this._vars[name] = value;
        },
        getVariable: function(name) {
          return this._vars[name] || '';
        }
      };
      
      // 模拟cache对象
      var cache = {
        _data: {},
        get: function(key) {
          return this._data[key] || '';
        },
        put: function(key, value, saveTime) {
          this._data[key] = value;
        },
        delete: function(key) {
          delete this._data[key];
        },
        deleteAll: function() {
          this._data = {};
        }
      };
      
      // ==================== Jsoup DOM解析器 ====================
      // 简化版Jsoup实现，用于HTML解析
      var Jsoup = {
        parse: function(html) {
          return new JsoupDocument(html);
        }
      };
      
      // Jsoup Document类
      function JsoupDocument(html) {
        this._html = html || '';
        this._title = '';
        // 提取title
        var titleMatch = this._html.match(/<title[^>]*>([^<]*)<\\/title>/i);
        if (titleMatch) {
          this._title = titleMatch[1];
        }
      }
      
      JsoupDocument.prototype.title = function() {
        return this._title;
      };
      
      JsoupDocument.prototype.select = function(selector) {
        return new JsoupElements(this._html, selector);
      };
      
      JsoupDocument.prototype.selectFirst = function(selector) {
        var elements = this.select(selector);
        return elements.size() > 0 ? elements.get(0) : new JsoupElement('');
      };
      
      JsoupDocument.prototype.html = function() {
        return this._html;
      };
      
      JsoupDocument.prototype.text = function() {
        return this._html.replace(/<[^>]+>/g, '').trim();
      };
      
      // Jsoup Elements集合类
      function JsoupElements(html, selector) {
        this._elements = [];
        this._parseElements(html, selector);
      }
      
      JsoupElements.prototype._parseElements = function(html, selector) {
        if (!html || !selector) return;
        
        // 解析选择器
        var tagName = '';
        var className = '';
        var idName = '';
        var attrName = '';
        var attrValue = '';
        
        // 解析选择器类型
        if (selector.indexOf('#') === 0) {
          idName = selector.substring(1);
        } else if (selector.indexOf('.') === 0) {
          className = selector.substring(1);
        } else if (selector.indexOf('[') !== -1) {
          var attrMatch = selector.match(/([\\w-]*)\\[([\\w-]+)(?:=[\"']?([^\"'\\]]*)[\"']?)?\\]/);
          if (attrMatch) {
            tagName = attrMatch[1] || '';
            attrName = attrMatch[2];
            attrValue = attrMatch[3] || '';
          }
        } else if (selector.indexOf(' ') !== -1) {
          // 后代选择器，简化处理：只取最后一个
          var parts = selector.split(' ');
          selector = parts[parts.length - 1];
          return this._parseElements(html, selector);
        } else {
          // 可能是 tag.class 或 tag#id 或纯tag
          var dotIndex = selector.indexOf('.');
          var hashIndex = selector.indexOf('#');
          if (dotIndex !== -1) {
            tagName = selector.substring(0, dotIndex);
            className = selector.substring(dotIndex + 1);
          } else if (hashIndex !== -1) {
            tagName = selector.substring(0, hashIndex);
            idName = selector.substring(hashIndex + 1);
          } else {
            tagName = selector;
          }
        }
        
        // 查找匹配的元素
        var regex;
        if (tagName && className) {
          regex = new RegExp('<' + tagName + '[^>]*class=[\"\\'][^\"\\']*\\\\b' + className + '\\\\b[^\"\\']*[\"\\'][^>]*>([\\\\s\\\\S]*?)<\\/' + tagName + '>', 'gi');
        } else if (tagName && idName) {
          regex = new RegExp('<' + tagName + '[^>]*id=[\"\\']' + idName + '[\"\\'][^>]*>([\\\\s\\\\S]*?)<\\/' + tagName + '>', 'gi');
        } else if (className) {
          regex = new RegExp('<([a-z][a-z0-9]*)[^>]*class=[\"\\'][^\"\\']*\\\\b' + className + '\\\\b[^\"\\']*[\"\\'][^>]*>([\\\\s\\\\S]*?)<\\\\/\\\\1>', 'gi');
        } else if (idName) {
          regex = new RegExp('<([a-z][a-z0-9]*)[^>]*id=[\"\\']' + idName + '[\"\\'][^>]*>([\\\\s\\\\S]*?)<\\\\/\\\\1>', 'gi');
        } else if (tagName) {
          // 自闭合标签特殊处理
          if (['img', 'br', 'hr', 'input', 'meta', 'link'].indexOf(tagName.toLowerCase()) !== -1) {
            regex = new RegExp('<' + tagName + '[^>]*\\/?>', 'gi');
          } else {
            regex = new RegExp('<' + tagName + '[^>]*>([\\\\s\\\\S]*?)<\\/' + tagName + '>', 'gi');
          }
        } else {
          return;
        }
        
        var match;
        while ((match = regex.exec(html)) !== null) {
          this._elements.push(new JsoupElement(match[0]));
        }
      };
      
      JsoupElements.prototype.size = function() {
        return this._elements.length;
      };
      
      JsoupElements.prototype.get = function(index) {
        return this._elements[index] || new JsoupElement('');
      };
      
      JsoupElements.prototype.first = function() {
        return this.get(0);
      };
      
      JsoupElements.prototype.last = function() {
        return this.get(this._elements.length - 1);
      };
      
      JsoupElements.prototype.text = function() {
        var texts = [];
        for (var i = 0; i < this._elements.length; i++) {
          texts.push(this._elements[i].text());
        }
        return texts.join(' ');
      };
      
      JsoupElements.prototype.html = function() {
        if (this._elements.length > 0) {
          return this._elements[0].html();
        }
        return '';
      };
      
      JsoupElements.prototype.attr = function(name) {
        if (this._elements.length > 0) {
          return this._elements[0].attr(name);
        }
        return '';
      };
      
      JsoupElements.prototype.eachAttr = function(name) {
        var attrs = [];
        for (var i = 0; i < this._elements.length; i++) {
          var val = this._elements[i].attr(name);
          if (val) attrs.push(val);
        }
        return attrs;
      };
      
      JsoupElements.prototype.eachText = function() {
        var texts = [];
        for (var i = 0; i < this._elements.length; i++) {
          texts.push(this._elements[i].text());
        }
        return texts;
      };
      
      // Jsoup Element类
      function JsoupElement(outerHtml) {
        this._outerHtml = outerHtml || '';
      }
      
      JsoupElement.prototype.text = function() {
        return this._outerHtml.replace(/<[^>]+>/g, '').trim();
      };
      
      JsoupElement.prototype.html = function() {
        // 提取内部HTML
        var match = this._outerHtml.match(/^<[^>]+>([\\s\\S]*)<\\/[^>]+>$/);
        return match ? match[1] : '';
      };
      
      JsoupElement.prototype.outerHtml = function() {
        return this._outerHtml;
      };
      
      JsoupElement.prototype.attr = function(name) {
        var regex = new RegExp(name + '=[\"\\']([^\"\\']*)[\"\\']', 'i');
        var match = this._outerHtml.match(regex);
        return match ? match[1] : '';
      };
      
      JsoupElement.prototype.select = function(selector) {
        return new JsoupElements(this._outerHtml, selector);
      };
      
      JsoupElement.prototype.selectFirst = function(selector) {
        var elements = this.select(selector);
        return elements.size() > 0 ? elements.get(0) : new JsoupElement('');
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
