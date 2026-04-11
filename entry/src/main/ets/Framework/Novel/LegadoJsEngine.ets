/**
 * Legado JavaScript执行引擎
 * 优先使用Native JSVM引擎执行书源中的JavaScript代码
 * 当Native引擎不可用时，降级到WebView执行
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets
 */

import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import { logger } from '../../Utils/Logger';
import { NativeJsEngine, JsContext as NativeJsContext, JsResult } from './NativeJsEngine';

const TAG = 'LegadoJsEngine';

/**
 * Toast消息
 */
export interface ToastMessage {
  type: 'short' | 'long';
  msg: string;
}

/**
 * Cookie变化记录
 */
export interface CookieChange {
  action: 'set' | 'remove';
  url: string;
  value?: string;
}

/**
 * JS执行结果
 */
export interface JsExecuteResult {
  success: boolean;
  result: string;
  error?: string;
  /** Toast消息列表，需要在ArkTS层显示 */
  toasts?: ToastMessage[];
  /** 日志消息列表 */
  logs?: string[];
  /** Cookie变化列表，需要同步到持久化存储 */
  cookieChanges?: CookieChange[];
}

/**
 * HTTP请求响应结果
 */
export interface HttpResponse {
  body: string;
  url: string;
  code: number;
  headers: string;
  error?: string;
}

/**
 * JS执行上下文
 */
export interface JsContext {
  /** 当前页面内容 */
  result?: string;
  /** 基础URL */
  baseUrl?: string;
  /** 书籍信息 */
  book?: Record<string, string>;
  /** 章节信息 */
  chapter?: Record<string, string>;
  /** 搜索关键字 */
  key?: string;
  /** 页码 */
  page?: number;
  /** 自定义变量 */
  variables?: Record<string, string>;
  /** 原始内容（与result相同，用于兼容） */
  src?: string;
  /** 本次执行绑定的jsLib快照（可选，优先级高于全局jsLib） */
  jsLib?: string;
  /** 书源对象 */
  source?: ESObject;
}

/**
 * 待执行任务
 */
interface PendingTask {
  code: string;
  context: JsContext;
  resolve: (result: JsExecuteResult) => void;
}

/**
 * 预获取结果
 */
interface PrefetchResult {
  url: string;
  result: HttpResponse;
}

/**
 * Legado JS执行引擎
 * 单例模式，优先使用Native JSVM引擎，降级到WebView
 */
export class LegadoJsEngine {
  private static instance: LegadoJsEngine | null = null;
  private webviewController: webview.WebviewController | null = null;
  private isReady: boolean = false;
  private pendingTasks: Array<PendingTask> = [];
  private jsLib: string = '';
  
  // Native JSVM引擎
  private nativeEngine: NativeJsEngine | null = null;
  private nativeEngineReady: boolean = false;
  private useNativeEngine: boolean = true; // 是否优先使用Native引擎

  private constructor() {
    // 尝试初始化Native引擎
    this.initNativeEngine();
  }
  
  /**
   * 初始化Native JSVM引擎
   */
  private async initNativeEngine(): Promise<void> {
    if (!this.useNativeEngine) {
      return;
    }
    
    try {
      this.nativeEngine = new NativeJsEngine();
      const success = await this.nativeEngine.initialize();
      if (success) {
        this.nativeEngineReady = true;
        logger.info(TAG, 'Native JSVM引擎初始化成功');
      } else {
        logger.warn(TAG, 'Native JSVM引擎初始化失败，将使用WebView');
        this.nativeEngine = null;
      }
    } catch (e) {
      logger.error(TAG, `Native JSVM引擎初始化异常: ${String(e)}`);
      this.nativeEngine = null;
      this.nativeEngineReady = false;
    }
  }

  static getInstance(): LegadoJsEngine {
    if (!LegadoJsEngine.instance) {
      LegadoJsEngine.instance = new LegadoJsEngine();
    }
    return LegadoJsEngine.instance;
  }

  /**
   * 设置WebView控制器
   */
  setWebviewController(controller: webview.WebviewController): void {
    this.webviewController = controller;
    this.isReady = true;
    logger.info(TAG, 'WebView控制器已设置');
    
    // 处理等待中的任务
    this.processPendingTasks();
  }

  /**
   * 设置JS库（书源的jsLib字段）
   */
  setJsLib(jsLib: string): void {
    this.jsLib = jsLib || '';
    if (jsLib && jsLib.length > 0) {
      logger.debug(TAG, `已设置jsLib (${jsLib.length}字符)`);
    }
  }

  /**
   * 使用ArkTS发起HTTP请求（绕过WebView的CORS限制）
   * @param url 请求URL
   * @param method 请求方法
   * @param body 请求体
   * @param headers 请求头
   * @returns 响应结果
   */
  async httpRequest(url: string, method: string = 'GET', body?: string, headers?: Record<string, string>): Promise<HttpResponse> {
    try {
      const httpRequest = http.createHttp();
      
      // 构建请求头
      const headerObj: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36'
      };
      if (headers) {
        const keys = Object.keys(headers);
        for (const key of keys) {
          headerObj[key] = headers[key];
        }
      }
      
      // 构建请求选项
      const options: http.HttpRequestOptions = {
        method: method === 'POST' ? http.RequestMethod.POST : 
                method === 'HEAD' ? http.RequestMethod.HEAD : http.RequestMethod.GET,
        header: headerObj,
        connectTimeout: 10000,
        readTimeout: 30000
      };
      
      if (body && method === 'POST') {
        options.extraData = body;
      }
      
      logger.debug(TAG, `[ArkTS HTTP] 发起请求: ${method} ${url}`);
      
      const response = await httpRequest.request(url, options);
      
      // 获取响应头字符串
      let headerStr = '';
      if (response.header) {
        const respHeaderObj = response.header as Record<string, string>;
        headerStr = Object.keys(respHeaderObj).map((k: string) => `${k}: ${respHeaderObj[k]}`).join('\r\n');
      }
      
      const result: HttpResponse = {
        body: typeof response.result === 'string' ? response.result : String(response.result || ''),
        url: url,
        code: response.responseCode,
        headers: headerStr
      };
      
      logger.debug(TAG, `[ArkTS HTTP] 请求成功: ${url}, 状态码: ${response.responseCode}, 响应长度: ${result.body.length}`);
      
      httpRequest.destroy();
      return result;
    } catch (e) {
      logger.error(TAG, `[ArkTS HTTP] 请求失败: ${url}, 错误: ${String(e)}`);
      const errorResult: HttpResponse = {
        body: '',
        url: url,
        code: 0,
        headers: '',
        error: String(e)
      };
      return errorResult;
    }
  }

  /**
   * 检测JS代码是否需要网络请求功能
   * 这些功能需要使用WebView执行（WebView支持XMLHttpRequest）
   */
  private needsNetworkCapability(code: string): boolean {
    // 明确需要网络请求的函数
    const networkPatterns = [
      'java.connect',
      'java.ajax',
      'java.ajaxAll',
      'java.post',
      'java.head',
      'java.webView',
      'java.cacheFile',
      'java.importScript',
      'java.startBrowserAwait'
    ];
    
    for (const pattern of networkPatterns) {
      if (code.includes(pattern)) {
        return true;
      }
    }
    
    // java.get 需要特殊处理：
    // - java.get("entityType") / java.get("n") 等字符串字面量变量读取，不需要网络
    // - java.get(urlVariable) / java.get("http...") 这类URL读取，才需要网络
    if (code.includes('java.get')) {
      const javaGetCallPattern = /java\.get\s*\(\s*([^)]+?)\s*\)/g;
      const matches = code.match(javaGetCallPattern) || [];
      for (let i = 0; i < matches.length; i++) {
        const fullCall = matches[i];
        const argMatch = fullCall.match(/java\.get\s*\(\s*([^)]+?)\s*\)/);
        if (!argMatch || argMatch.length < 2) {
          return true;
        }

        const arg = argMatch[1].trim();
        const isDoubleQuoted = arg.startsWith('"') && arg.endsWith('"');
        const isSingleQuoted = arg.startsWith("'") && arg.endsWith("'");
        if (isDoubleQuoted || isSingleQuoted) {
          const literal = arg.substring(1, arg.length - 1).trim();
          if (literal.length <= 0) {
            continue;
          }
          if (
            literal.includes('://') ||
            literal.startsWith('/') ||
            literal.startsWith('resource://')
          ) {
            return true;
          }
          continue;
        }

        // 非字面量参数（变量/表达式）按网络请求处理
        return true;
      }
    }
    
    return false;
  }
  
  /**
   * 执行JavaScript代码
   * 智能选择执行引擎：
   * - 需要网络请求的代码 -> WebView执行（支持XMLHttpRequest）
   * - 简单计算/字符串处理 -> Native JSVM执行
   */
  async execute(code: string, context: JsContext = {}): Promise<JsExecuteResult> {
    if (!code || code.trim() === '') {
      return { success: true, result: '' };
    }

    // 检测是否需要网络请求功能
    const needsNetwork = this.needsNetworkCapability(code);
    
    // 如果需要网络请求，直接使用WebView执行（WebView支持XMLHttpRequest同步请求）
    // 注意：Native JSVM不支持网络请求，因为HarmonyOS没有libcurl
    if (needsNetwork) {
      logger.debug(TAG, `JS代码包含网络请求函数，使用WebView执行`);
      if (this.canUseWebView()) {
        return this.enqueueWebViewTask(code, context);
      }
      
      // WebView不可用时，尝试简单求值（网络请求功能将不可用）
      logger.warn(TAG, 'WebView不可用，网络请求功能将无法使用');
    }

    // 不需要网络请求或WebView不可用，尝试使用Native JSVM引擎
    if (this.nativeEngineReady && this.nativeEngine) {
      try {
        // 构建完整的执行脚本（包含辅助函数和上下文）
        const fullScript = this.buildNativeScript(code, context);
        
        const nativeContext: NativeJsContext = {
          result: context.result,
          baseUrl: context.baseUrl,
          key: context.key,
          page: context.page,
          sourceUrl: context.variables?.['sourceUrl'] || context.baseUrl,
          variables: context.variables
        };
        
        const result = await this.nativeEngine.execute(fullScript, nativeContext);
        if (result.success) {
          const nativeError = this.extractErrorFromResult(result.result);
          if (nativeError) {
            logger.warn(TAG, `Native执行错误: ${nativeError}`);
            if (this.canUseWebView()) {
              logger.info(TAG, 'Native执行结果包含错误，回退到WebView重试');
              return this.enqueueWebViewTask(code, context);
            }
            return { success: true, result: '', error: nativeError };
          }
          logger.debug(TAG, `Native执行结果: ${result.result ? result.result.substring(0, 100) : '(空)'}`);
          return { success: true, result: result.result };
        }
        // Native执行失败
        const nativeFailure = result.error || 'Native执行失败';
        logger.warn(TAG, `Native执行失败: ${nativeFailure}`);
        if (this.canUseWebView()) {
          logger.info(TAG, 'Native执行失败，回退到WebView重试');
          return this.enqueueWebViewTask(code, context);
        }
        return { success: false, result: '', error: nativeFailure };
      } catch (e) {
        const exceptionError = String(e);
        logger.error(TAG, `Native执行异常: ${exceptionError}`);
        if (this.canUseWebView()) {
          logger.info(TAG, 'Native执行异常，回退到WebView重试');
          return this.enqueueWebViewTask(code, context);
        }
        return { success: false, result: '', error: exceptionError };
      }
    }
    
    // Native引擎未就绪，等待初始化完成后重试
    if (this.useNativeEngine && !this.nativeEngineReady) {
      // 等待Native引擎初始化（最多等待2秒）
      for (let i = 0; i < 20; i++) {
        await new Promise<void>(resolve => setTimeout(resolve, 100));
        if (this.nativeEngineReady && this.nativeEngine) {
          // 引擎已就绪，重新执行
          return this.execute(code, context);
        }
      }
      logger.warn(TAG, 'Native引擎初始化超时，尝试使用WebView');
    }

    // 降级到WebView执行（仅当Native引擎不可用时）
    if (this.canUseWebView()) {
      return this.enqueueWebViewTask(code, context);
    }

    // 最后使用简单的表达式求值（仅当所有引擎都不可用时）
    logger.warn(TAG, 'Native和WebView都不可用，使用简单求值');
    return this.executeSimple(code, context);
  }

  private canUseWebView(): boolean {
    return this.isReady && this.webviewController !== null;
  }

  private enqueueWebViewTask(code: string, context: JsContext): Promise<JsExecuteResult> {
    return new Promise((resolve) => {
      const task: PendingTask = {
        code: code,
        context: context,
        resolve: resolve
      };
      this.pendingTasks.push(task);
      this.processPendingTasks();
    });
  }

  /**
   * 构建上下文变量代码
   */
  private buildContextVars(context: JsContext): string {
    const vars: string[] = [];
    
    if (context.result !== undefined) {
      vars.push(`var result = ${JSON.stringify(context.result)};`);
    } else {
      vars.push(`var result = '';`);
    }
    
    if (context.baseUrl !== undefined) {
      vars.push(`var baseUrl = ${JSON.stringify(context.baseUrl)};`);
    } else {
      vars.push(`var baseUrl = '';`);
    }

    if (context.src !== undefined) {
      vars.push(`var src = ${JSON.stringify(context.src)};`);
    } else if (context.result !== undefined) {
      vars.push(`var src = ${JSON.stringify(context.result)};`);
    } else {
      vars.push(`var src = '';`);
    }
    
    if (context.key !== undefined) {
      vars.push(`var key = ${JSON.stringify(context.key)};`);
    } else {
      vars.push(`var key = '';`);
    }
    
    if (context.page !== undefined) {
      vars.push(`var page = ${context.page};`);
    } else {
      vars.push(`var page = 1;`);
    }
    
    vars.push(`var sourceUrl = ${JSON.stringify(context.variables?.['sourceUrl'] || context.baseUrl || '')};`);
    
    return vars.join('\\n');
  }

  /**
   * 构建自定义变量代码
   */
  private buildVariableVars(context: JsContext): string {
    if (!context.variables) {
      return '';
    }
    
    const vars: string[] = [];
    const entries = Object.entries(context.variables);
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      const key = entry[0];
      const value = entry[1];
      if (key !== 'sourceUrl') { // sourceUrl已在buildContextVars中处理
        vars.push(`var ${key} = ${JSON.stringify(value)};`);
      }
    }
    
    return vars.join('\\n');
  }

  /**
   * 处理等待中的任务
   */
  private async processPendingTasks(): Promise<void> {
    if (!this.isReady || !this.webviewController || this.pendingTasks.length === 0) {
      return;
    }

    const task = this.pendingTasks.shift();
    if (!task) {
      return;
    }

    logger.debug(TAG, `开始执行WebView JS任务，剩余队列: ${this.pendingTasks.length}`);
    
    try {
      const result = await this.executeInWebView(task.code, task.context);
      logger.debug(TAG, `WebView JS任务执行完成，success=${result.success}`);
      task.resolve(result);
    } catch (error) {
      logger.error(TAG, `WebView JS任务执行异常: ${String(error)}`);
      task.resolve({
        success: false,
        result: '',
        error: String(error)
      });
    }

    // 继续处理下一个任务
    if (this.pendingTasks.length > 0) {
      logger.debug(TAG, `继续处理下一个任务，剩余: ${this.pendingTasks.length}`);
      this.processPendingTasks();
    }
  }

  /**
   * 从代码中提取可能的URL（用于预先发起网络请求）
   */
  private extractUrls(code: string): string[] {
    const urls: string[] = [];
    // 匹配常见的URL模式
    const urlPatterns = [
      /["'](https?:\/\/[^"'\s]+)["']/g,  // 引号中的URL
      /url\s*[=:]\s*["']([^"']+)["']/gi,  // url = "..." 或 url: "..."
    ];
    
    for (const pattern of urlPatterns) {
      let match: RegExpExecArray | null;
      while ((match = pattern.exec(code)) !== null) {
        const url = match[1];
        if (url && !urls.includes(url) && (url.startsWith('http://') || url.startsWith('https://'))) {
          urls.push(url);
        }
      }
    }
    
    return urls;
  }

  /**
   * 预先通过ArkTS发起网络请求，并将结果注入到WebView缓存中
   */
  private async prefetchUrls(urls: string[]): Promise<void> {
    if (urls.length === 0 || !this.webviewController) {
      return;
    }
    
    logger.debug(TAG, `[Prefetch] 预先获取 ${urls.length} 个URL`);
    
    // 并行发起所有请求
    const results: PrefetchResult[] = [];
    for (const url of urls) {
      const result = await this.httpRequest(url, 'GET');
      const prefetchResult: PrefetchResult = { url: url, result: result };
      results.push(prefetchResult);
    }
    
    // 构建缓存注入脚本
    const cacheEntries: string[] = [];
    for (let i = 0; i < results.length; i++) {
      const item = results[i];
      const url = item.url;
      const result = item.result;
      const cacheKey = `GET:${url}`;
      // 转义特殊字符
      const escapedBody = JSON.stringify(result.body);
      const escapedHeaders = JSON.stringify(result.headers);
      cacheEntries.push(`
        window.__httpCache["${cacheKey}"] = {
          body: ${escapedBody},
          url: "${url}",
          code: ${result.code},
          headers: ${escapedHeaders}
        };
      `);
    }
    
    if (cacheEntries.length > 0) {
      const injectScript = `
        (function() {
          window.__httpCache = window.__httpCache || {};
          ${cacheEntries.join('\n')}
          console.log('[Prefetch] 已注入 ${cacheEntries.length} 个URL缓存');
        })();
      `;
      
      try {
        await this.webviewController.runJavaScript(injectScript);
        logger.debug(TAG, `[Prefetch] 成功注入 ${cacheEntries.length} 个URL缓存到WebView`);
      } catch (e) {
        logger.error(TAG, `[Prefetch] 注入缓存失败: ${String(e)}`);
      }
    }
  }

  /**
   * 在WebView中执行JavaScript（带超时保护）
   */
  private async executeInWebView(code: string, context: JsContext): Promise<JsExecuteResult> {
    if (!this.webviewController) {
      return { success: false, result: '', error: 'WebView未初始化' };
    }

    try {
      // 注意：不再预获取所有URL，因为：
      // 1. 从代码中提取的URL可能包含jsLib中的无关URL
      // 2. 实际需要请求的URL可能是动态生成的
      // 3. 预获取会导致大量不必要的网络请求
      // 改为：在__syncRequest中，如果XMLHttpRequest失败，会记录请求信息
      // 然后我们可以在需要时重新执行脚本
      
      // 构建执行脚本
      const script = this.buildScript(code, context);
      const scriptLiteral = JSON.stringify(script)
        .replace(/\u2028/g, '\\u2028')
        .replace(/\u2029/g, '\\u2029');
      
      // 包装脚本以捕获执行结果、错误、日志、Toast消息和Cookie变化
      // 注意：不再嵌套buildScript的IIFE，直接执行其内部代码
      // 重要：WebView的runJavaScript需要脚本返回一个字符串值
      const wrappedScript = `
        (function() {
          var __logs = [];
          var __errors = [];
          window.__toasts = window.__toasts || [];
          window.__cookieChanges = window.__cookieChanges || [];
          var __originalLog = console.log;
          var __originalError = console.error;
          console.log = function() {
            var args = Array.prototype.slice.call(arguments);
            var msg = args.map(function(a) { return String(a); }).join(' ');
            __logs.push(msg);
            if (__originalLog) __originalLog.apply(console, arguments);
          };
          console.error = function() {
            var args = Array.prototype.slice.call(arguments);
            var msg = args.map(function(a) { return String(a); }).join(' ');
            __errors.push(msg);
            __logs.push('[ERROR] ' + msg);
            if (__originalError) __originalError.apply(console, arguments);
          };
          window.onerror = function(msg, url, line, col, error) {
            __errors.push('Window Error: ' + msg + ' at line ' + line);
            return true;
          };
          
          var __scriptResult;
          var __scriptError = null;
          
          try {
            console.log('[WebView] 开始执行脚本...');
            // 使用eval执行脚本字符串，避免模板字符串嵌入导致的语法问题
            __scriptResult = eval(${scriptLiteral});
            console.log('[WebView] 脚本执行完成，结果:', typeof __scriptResult, __scriptResult ? String(__scriptResult).substring(0, 100) : 'null/undefined');
          } catch(e) {
            __scriptError = e.message || String(e);
            console.error('[WebView] 脚本执行错误:', __scriptError);
            if (e.stack) console.error('Stack:', e.stack);
          }
          
          // 收集toast消息和cookie变化
          var __toasts = window.__toasts || [];
          var __cookies = window.__cookieChanges || [];
          
          // 构建返回结果
          var __returnObj;
          if (__scriptError) {
            __returnObj = {
              __error: __scriptError,
              __logs: __logs,
              __toasts: __toasts,
              __cookies: __cookies
            };
          } else {
            __returnObj = {
              __result: __scriptResult !== undefined && __scriptResult !== null ? String(__scriptResult) : '',
              __logs: __logs,
              __toasts: __toasts,
              __cookies: __cookies
            };
          }
          
          try {
            return JSON.stringify(__returnObj);
          } catch(jsonErr) {
            return JSON.stringify({ __error: 'JSON序列化失败: ' + jsonErr.message, __logs: __logs });
          }
        })()
      `;
      
      // 执行脚本（带超时保护，防止无限循环导致卡住）
      const TIMEOUT_MS = 30000; // 30秒超时
      logger.debug(TAG, `执行WebView脚本，脚本长度: ${wrappedScript.length}`);
      
      // 输出脚本的关键部分用于调试
      logger.debug(TAG, `脚本开头200字符: ${wrappedScript.substring(0, 200)}`);
      
      // 输出buildScript生成的脚本的前500字符，用于调试
      logger.debug(TAG, `buildScript生成的脚本前500字符: ${script.substring(0, 500)}`);
      
      // 检查脚本是否有明显的语法问题
      // 尝试用一个简单的方式检测脚本是否能被解析
      try {
        const syntaxCheckScript = `
          (function() {
            try {
              // 尝试创建一个Function来检查语法
              var testCode = ${scriptLiteral};
              new Function(testCode);
              return JSON.stringify({ syntaxOk: true });
            } catch(e) {
              return JSON.stringify({ syntaxOk: false, error: e.message, line: e.lineNumber || 'unknown' });
            }
          })()
        `;
        const syntaxResult = await this.webviewController!.runJavaScript(syntaxCheckScript);
        logger.debug(TAG, `语法检查结果: ${syntaxResult}`);
      } catch (syntaxError) {
        logger.error(TAG, `语法检查失败: ${String(syntaxError)}`);
      }
      
      // 先测试WebView是否能正常执行简单脚本
      try {
        const testResult = await this.webviewController!.runJavaScript('(function(){ return JSON.stringify({test:"ok"}); })()');
        logger.debug(TAG, `WebView测试脚本结果: ${testResult}`);
      } catch (testError) {
        logger.error(TAG, `WebView测试脚本失败: ${String(testError)}`);
      }
      
      // 尝试执行一个简化版本的脚本来测试
      const simpleTestScript = `
        (function() {
          try {
            var result = "simple_test_ok";
            return JSON.stringify({ __result: result, __logs: [] });
          } catch(e) {
            return JSON.stringify({ __error: e.message });
          }
        })()
      `;
      try {
        const simpleResult = await this.webviewController!.runJavaScript(simpleTestScript);
        logger.debug(TAG, `简化测试脚本结果: ${simpleResult}`);
      } catch (simpleError) {
        logger.error(TAG, `简化测试脚本失败: ${String(simpleError)}`);
      }
      
      const result = await this.runJavaScriptWithTimeout(wrappedScript, TIMEOUT_MS);
      logger.debug(TAG, `WebView脚本执行原始结果: [${typeof result}] ${result ? result.substring(0, 500) : 'null/empty'}`);
      
      // 如果结果为空，尝试获取WebView的错误信息
      if (!result || result === '' || result === 'null') {
        logger.warn(TAG, `脚本执行返回空结果，脚本长度: ${wrappedScript.length}，可能是脚本太大或有语法错误`);
        // 尝试执行一个简单的错误检测脚本
        try {
          const errorCheckScript = `
            (function() {
              try {
                // 检查window上是否有错误信息
                var errors = [];
                if (window.__lastError) errors.push(window.__lastError);
                if (window.onerror) errors.push('onerror handler exists');
                return JSON.stringify({ check: 'ok', errors: errors });
              } catch(e) {
                return JSON.stringify({ check: 'error', message: e.message });
              }
            })()
          `;
          const errorCheckResult = await this.webviewController!.runJavaScript(errorCheckScript);
          logger.debug(TAG, `错误检测结果: ${errorCheckResult}`);
        } catch (checkError) {
          logger.error(TAG, `错误检测失败: ${String(checkError)}`);
        }
      }
      
      // 解析结果
      if (result) {
        try {
          const parsed = JSON.parse(result) as Record<string, ESObject>;
          
          // 提取toast消息
          const toasts: ToastMessage[] = [];
          if (parsed['__toasts'] && Array.isArray(parsed['__toasts'])) {
            const rawToasts = parsed['__toasts'] as Array<Record<string, string>>;
            for (const t of rawToasts) {
              toasts.push({
                type: t['type'] === 'long' ? 'long' : 'short',
                msg: String(t['msg'] || '')
              });
            }
            if (toasts.length > 0) {
              logger.debug(TAG, `收集到 ${toasts.length} 条Toast消息`);
            }
          }
          
          // 提取日志
          const logs: string[] = parsed['__logs'] ? parsed['__logs'] as string[] : [];
          if (logs.length > 0) {
            logger.debug(TAG, `JS日志: ${JSON.stringify(logs)}`);
          }
          
          // 提取cookie变化
          const cookieChanges: CookieChange[] = [];
          if (parsed['__cookies'] && Array.isArray(parsed['__cookies'])) {
            const rawCookies = parsed['__cookies'] as Array<Record<string, string>>;
            for (const c of rawCookies) {
              cookieChanges.push({
                action: c['action'] === 'remove' ? 'remove' : 'set',
                url: String(c['url'] || ''),
                value: c['value'] ? String(c['value']) : undefined
              });
            }
            if (cookieChanges.length > 0) {
              logger.debug(TAG, `收集到 ${cookieChanges.length} 条Cookie变化`);
            }
          }
          
          if (parsed['__error']) {
            logger.error(TAG, `JS执行错误: ${parsed['__error']}`);
            return {
              success: false,
              result: '',
              error: String(parsed['__error']),
              toasts: toasts,
              logs: logs,
              cookieChanges: cookieChanges
            };
          }
          
          // 优先返回脚本执行结果
          if (parsed['__result'] !== undefined) {
            const parsedResult = String(parsed['__result']);
            const parsedError = this.extractErrorFromResult(parsedResult);
            if (parsedError) {
              logger.error(TAG, `JS执行错误: ${parsedError}`);
              return {
                success: false,
                result: '',
                error: parsedError,
                toasts: toasts,
                logs: logs,
                cookieChanges: cookieChanges
              };
            }
            return {
              success: true,
              result: parsedResult,
              toasts: toasts,
              logs: logs,
              cookieChanges: cookieChanges
            };
          }
          
          // 如果没有结果但有日志，返回日志
          if (logs.length > 0) {
            return {
              success: true,
              result: logs.join('\n'),
              toasts: toasts,
              logs: logs,
              cookieChanges: cookieChanges
            };
          }
          
          return {
            success: true,
            result: '',
            toasts: toasts,
            logs: logs,
            cookieChanges: cookieChanges
          };
        } catch (e) {
          // 不是JSON，直接返回
        }
      }
      
      const plainResult = result ? String(result) : '';
      const plainError = this.extractErrorFromResult(plainResult);
      if (plainError) {
        logger.error(TAG, `JS执行错误: ${plainError}`);
        return {
          success: false,
          result: '',
          error: plainError
        };
      }

      return {
        success: true,
        result: plainResult
      };
    } catch (error) {
      logger.error(TAG, `JS执行失败: ${String(error)}`);
      return {
        success: false,
        result: '',
        error: String(error)
      };
    }
  }

  /**
   * 带超时的JavaScript执行
   * 防止无限循环导致永久卡住
   */
  private async runJavaScriptWithTimeout(script: string, timeoutMs: number): Promise<string> {
    if (!this.webviewController) {
      throw new Error('WebView未初始化');
    }

    return new Promise<string>((resolve, reject) => {
      let isResolved = false;
      
      // 超时定时器
      const timeoutId = setTimeout(() => {
        if (!isResolved) {
          isResolved = true;
          logger.warn(TAG, `JS执行超时(${timeoutMs}ms)，可能存在无限循环`);
          reject(new Error(`JS执行超时(${timeoutMs}ms)`));
        }
      }, timeoutMs);

      // 执行脚本
      this.webviewController!.runJavaScript(script)
        .then((result: string) => {
          if (!isResolved) {
            isResolved = true;
            clearTimeout(timeoutId);
            logger.debug(TAG, `runJavaScript原始返回类型: ${typeof result}, 值: ${result === null ? 'null' : result === undefined ? 'undefined' : String(result).substring(0, 100)}`);
            // WebView的runJavaScript返回的是字符串，如果是"null"字符串需要特殊处理
            if (result === null || result === undefined || result === 'null' || result === 'undefined') {
              resolve('');
            } else {
              // 如果返回值被双重引号包裹（JSON字符串），需要解析
              let finalResult = String(result);
              if (finalResult.startsWith('"') && finalResult.endsWith('"')) {
                try {
                  finalResult = JSON.parse(finalResult) as string;
                } catch (e) {
                  // 解析失败，保持原值
                }
              }
              resolve(finalResult);
            }
          }
        })
        .catch((error: Error) => {
          if (!isResolved) {
            isResolved = true;
            clearTimeout(timeoutId);
            logger.error(TAG, `runJavaScript执行错误: ${String(error)}`);
            reject(error);
          }
        });
    });
  }

  private extractErrorFromResult(rawResult: string): string | undefined {
    const normalized = rawResult.trim();
    if (!normalized) {
      return undefined;
    }
    if (normalized.startsWith('ERROR:')) {
      return normalized.substring(6).trim();
    }
    if (normalized.startsWith('Error:')) {
      return normalized.substring(6).trim();
    }
    if (normalized.startsWith('TypeError:') ||
        normalized.startsWith('SyntaxError:') ||
        normalized.startsWith('ReferenceError:')) {
      return normalized;
    }
    return undefined;
  }

  private normalizeJsCode(code: string): string {
    let normalized = code.trim();
    normalized = normalized.replace(/^(?:@|＠)\s*js(?:\:|：)\s*/i, '');
    if (normalized.startsWith('<js>') && normalized.endsWith('</js>')) {
      normalized = normalized.substring(4, normalized.length - 5).trim();
    }
    return normalized;
  }

  /**
   * 构建执行脚本
   */
  private buildScript(code: string, context: JsContext): string {
    // 获取sourceUrl（优先从variables中获取，否则使用baseUrl）
    const sourceUrl = context.variables?.['sourceUrl'] || context.baseUrl || '';
    const activeJsLib = context.jsLib !== undefined ? context.jsLib : this.jsLib;
    const sourceBookSourceName = context.variables?.['__source_bookSourceName'] || '';
    const sourceBookSourceGroup = context.variables?.['__source_bookSourceGroup'] || '';
    const sourceBookSourceComment = context.variables?.['__source_bookSourceComment'] || '';
    const sourceHeader = context.variables?.['__source_header'] || '';
    const sourceLoginUrl = context.variables?.['__source_loginUrl'] || '';
    const sourceLoginUi = context.variables?.['__source_loginUi'] || '';
    const sourceLoginCheckJs = context.variables?.['__source_loginCheckJs'] || '';
    const sourceVariableComment = context.variables?.['__source_variableComment'] || '';
    const normalizedSourceLoginUrl = this.normalizeJsCode(sourceLoginUrl);
    const normalizedSourceLoginCheckJs = this.normalizeJsCode(sourceLoginCheckJs);
    
    // 构建上下文变量
    // 注意：result需要特殊处理，如果是JSON字符串则解析为对象，否则保持字符串
    const resultStr = context.result || '';
    let resultVar = '';
    if (resultStr.startsWith('{') || resultStr.startsWith('[')) {
      // 尝试作为JSON对象/数组，这样JS代码可以直接访问属性如result.book_id
      resultVar = `var result = (function() { try { return JSON.parse(${JSON.stringify(resultStr)}); } catch(e) { return ${JSON.stringify(resultStr)}; } })();`;
    } else {
      resultVar = `var result = ${JSON.stringify(resultStr)};`;
    }
    
    const contextVars = `
      ${resultVar}
      var baseUrl = ${JSON.stringify(context.baseUrl || '')};
      var src = ${JSON.stringify(context.src !== undefined ? context.src : resultStr)};
      var sourceUrl = ${JSON.stringify(sourceUrl)};
      var key = ${JSON.stringify(context.key || '')};
      var page = ${context.page || 1};
      var book = ${JSON.stringify(context.book || {})};
      var chapter = ${JSON.stringify(context.chapter || {})};
      var __ctx_variables = ${JSON.stringify(context.variables || {})};
    `;

    // 构建变量
    let variableVars = '';
    if (context.variables) {
      const keys = Object.keys(context.variables);
      for (let i = 0; i < keys.length; i++) {
        const varKey = keys[i];
        const varValue = context.variables[varKey];
        // 跳过sourceUrl，已经在contextVars中定义
        if (varKey === 'sourceUrl') continue;
        if (!/^[A-Za-z_$][0-9A-Za-z_$]*$/.test(varKey)) {
          logger.warn(TAG, `跳过非法JS变量名: ${varKey}`);
          continue;
        }
        variableVars += `var ${varKey} = ${JSON.stringify(varValue)};\n`;
      }
    }

    // 添加常用工具函数（兼容Legado原版JsExtensions）
    const utilFunctions = `
      // 书源变量存储（用于source.getVariable/setVariable）
      var __sourceVariableStore = {};
      
      // 注入的登录信息（由外部传入）
      var __injectedLoginInfo = (typeof __loginInfo !== 'undefined') ? __loginInfo : '';
      var __injectedLoginHeader = (typeof __loginHeader !== 'undefined') ? __loginHeader : '';
      var __injectedSourceVariable = (typeof __sourceVariable !== 'undefined') ? __sourceVariable : '';
      
      // source对象 - 模拟书源对象
      // sourceUrl是书源的bookSourceUrl，用于source.getKey()
      var source = {
        getKey: function() { return sourceUrl || baseUrl || ''; },
        bookSourceUrl: sourceUrl || baseUrl || '',
        bookSourceName: ${JSON.stringify(sourceBookSourceName)},
        bookSourceGroup: ${JSON.stringify(sourceBookSourceGroup)},
        bookSourceComment: ${JSON.stringify(sourceBookSourceComment)},
        loginUrl: ${JSON.stringify(normalizedSourceLoginUrl)},
        loginUi: ${JSON.stringify(sourceLoginUi)},
        loginCheckJs: ${JSON.stringify(normalizedSourceLoginCheckJs)},
        header: ${JSON.stringify(sourceHeader)},
        variableComment: ${JSON.stringify(sourceVariableComment)},
        // 获取书源变量（Legado原版：用于存储书源的自定义配置）
        getVariable: function() { 
          var key = sourceUrl || baseUrl || 'default';
          if (__injectedSourceVariable) return __injectedSourceVariable;
          return __sourceVariableStore[key] || ''; 
        },
        // 设置书源变量
        setVariable: function(value) { 
          var key = sourceUrl || baseUrl || 'default';
          __sourceVariableStore[key] = value;
          __injectedSourceVariable = value;
          return value;
        },
        // 获取登录信息
        getLoginInfo: function() { return __injectedLoginInfo; },
        getLoginInfoMap: function() { 
          try { return __injectedLoginInfo ? JSON.parse(__injectedLoginInfo) : {}; } 
          catch(e) { return {}; } 
        },
        // 获取登录头信息
        getLoginHeader: function() { return __injectedLoginHeader; },
        getLoginHeaderMap: function() {
          try { return __injectedLoginHeader ? JSON.parse(__injectedLoginHeader) : {}; }
          catch(e) { return {}; }
        },
        // 获取书源头信息
        getHeaderMap: function() {
          try { return this.header ? JSON.parse(this.header) : {}; }
          catch(e) { return {}; }
        },
        // 登录信息存储
        putLoginInfo: function(info) { 
          __injectedLoginInfo = typeof info === 'string' ? info : JSON.stringify(info);
          return info; 
        },
        // 保存登录头信息
        putLoginHeader: function(header) {
          __injectedLoginHeader = typeof header === 'string' ? header : JSON.stringify(header);
          return header;
        },
        // 删除登录头信息
        removeLoginHeader: function() { __injectedLoginHeader = ''; },
        // 通用数据存储
        put: function(key, value) { __sourceVariableStore['data_' + key] = value; return value; },
        get: function(key) { return __sourceVariableStore['data_' + key] || ''; }
      };
      
      // book对象 - 模拟书籍对象（用于章节解析等场景）
      var __bookVariableStore = {};
      var book = book || {
        name: '',
        author: '',
        bookUrl: baseUrl || '',
        tocUrl: '',
        durChapterIndex: 0,
        durChapterTitle: '',
        readConfig: { useReplaceRule: true },
        // 获取书籍变量
        getVariable: function(key) {
          if (key) return __bookVariableStore[key] || '';
          return JSON.stringify(__bookVariableStore);
        },
        // 设置书籍变量
        putVariable: function(key, value) {
          __bookVariableStore[key] = value;
          return value;
        },
        // 设置是否使用替换规则
        setUseReplaceRule: function(use) {
          this.readConfig = this.readConfig || {};
          this.readConfig.useReplaceRule = use;
        }
      };
      
      // chapter对象 - 模拟章节对象
      var chapter = chapter || {
        index: 0,
        title: '',
        url: '',
        isVip: false,
        isPay: false,
        getVariable: function(key) { return ''; },
        putVariable: function(key, value) { return value; }
      };
      
      // cookie变量 - 用于存储和获取cookie
      // 使用内存存储，执行完成后会将变化同步到ArkTS层的持久化存储
      var __cookieStore = {};
      window.__cookieChanges = []; // 记录cookie变化，用于同步到持久化存储
      var cookie = {
        getCookie: function(url) { 
          try { return __cookieStore[url] || document.cookie || ''; } 
          catch(e) { return __cookieStore[url] || ''; }
        },
        setCookie: function(url, value) { 
          __cookieStore[url] = value;
          // 记录cookie变化
          window.__cookieChanges.push({ action: 'set', url: url, value: value });
          try { document.cookie = value; } catch(e) { /* ignore */ }
        },
        removeCookie: function(url) { 
          delete __cookieStore[url];
          // 记录cookie删除
          window.__cookieChanges.push({ action: 'remove', url: url });
          try { document.cookie = ''; } catch(e) { /* ignore */ }
        },
        // 从cookie字符串中获取指定key的值
        getKey: function(cookieStr, key) {
          if (!cookieStr) return '';
          if (!key) return cookieStr;
          var regex = new RegExp(key + '=([^;]*)');
          var match = cookieStr.match(regex);
          return match ? match[1] : '';
        },
        // 合并cookie
        mergeCookie: function(url, newCookie) {
          var existing = this.getCookie(url) || '';
          if (!existing) {
            this.setCookie(url, newCookie);
            return newCookie;
          }
          // 解析并合并
          var cookies = {};
          existing.split(';').forEach(function(part) {
            var eqIdx = part.indexOf('=');
            if (eqIdx > 0) {
              cookies[part.substring(0, eqIdx).trim()] = part.substring(eqIdx + 1).trim();
            }
          });
          newCookie.split(';').forEach(function(part) {
            var eqIdx = part.indexOf('=');
            if (eqIdx > 0) {
              cookies[part.substring(0, eqIdx).trim()] = part.substring(eqIdx + 1).trim();
            }
          });
          var merged = Object.keys(cookies).map(function(k) { return k + '=' + cookies[k]; }).join('; ');
          this.setCookie(url, merged);
          return merged;
        },
        cookieJar: __cookieStore
      };
      
      // cache对象 - 内存缓存
      var __cacheStore = {};
      var cache = {
        get: function(key) { return __cacheStore[key] || ''; },
        put: function(key, value) { __cacheStore[key] = value; return value; },
        getMemory: function(key) { return __cacheStore['mem_' + key] || ''; },
        putMemory: function(key, value) { __cacheStore['mem_' + key] = value; return value; },
        delete: function(key) { delete __cacheStore[key]; },
        deleteMemory: function(key) { delete __cacheStore['mem_' + key]; }
      };
      
      // putLoginInfo函数（全局）
      var putLoginInfo = function(info) { return info; };
      
      // 预注入的网络请求结果缓存（由ArkTS层填充）
      window.__httpCache = window.__httpCache || {};
      
      // 同步HTTP请求辅助函数
      // 优先从ArkTS预注入的缓存中获取结果，避免CORS限制
      // 如果缓存中没有，则尝试XMLHttpRequest（可能会因CORS失败）
      var __syncRequest = function(url, method, body, headers) {
        method = method || 'GET';
        
        // 生成缓存键
        var cacheKey = method + ':' + url;
        if (body) {
          cacheKey += ':' + body;
        }
        
        // 检查预注入的缓存
        if (window.__httpCache && window.__httpCache[cacheKey]) {
          console.log('[__syncRequest] 从缓存获取: ' + url);
          return window.__httpCache[cacheKey];
        }
        
        // 缓存中没有，尝试XMLHttpRequest
        try {
          var xhr = new XMLHttpRequest();
          xhr.open(method, url, false); // false = 同步
          // 注意：同步请求不能设置timeout，会抛出InvalidAccessError
          if (headers) {
            for (var key in headers) {
              if (headers.hasOwnProperty(key)) {
                xhr.setRequestHeader(key, headers[key]);
              }
            }
          }
          if (!headers || !headers['User-Agent']) {
            xhr.setRequestHeader('User-Agent', 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36');
          }
          xhr.send(body || null);
          var result = {
            body: xhr.responseText,
            url: xhr.responseURL || url,
            code: xhr.status,
            headers: xhr.getAllResponseHeaders()
          };
          // 缓存结果供后续使用
          window.__httpCache[cacheKey] = result;
          return result;
        } catch(e) {
          console.error('__syncRequest error:', e);
          // XMLHttpRequest失败，发送请求到ArkTS层
          // 通过特殊的console.log消息请求ArkTS代理
          console.log('__NATIVE_HTTP_REQUEST__:' + JSON.stringify({
            url: url,
            method: method,
            body: body || '',
            headers: headers || {}
          }));
          // 返回空结果，等待ArkTS层处理后重新执行
          return { body: '', url: url, code: 0, error: 'CORS_BLOCKED_NEED_NATIVE_PROXY' };
        }
      };
      
      // JavaImporter polyfill（Rhino特有功能，在标准JS中不可用）
      // 返回带基础能力的兼容对象，避免书源中将java覆盖后缺少常用API
      var JavaImporter = function() {
        var __uuidValueFactory = function() {
          if (typeof java !== 'undefined' && java && typeof java.randomUUID === 'function') {
            return java.randomUUID();
          }
          return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0;
            var v = c === 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
          });
        };
        return {
          util: {
            UUID: {
              randomUUID: function() {
                var value = __uuidValueFactory();
                return {
                  toString: function() { return value; }
                };
              }
            }
          }
        };
      };
      
      // Packages polyfill（Rhino特有功能，用于访问Java包）
      // 返回一个代理对象，避免书源中使用Packages时报错
      var Packages = new Proxy({}, {
        get: function(target, prop) {
          return new Proxy({}, {
            get: function(t, p) { return function() { return ''; }; }
          });
        }
      });
      
      // 保存上下文变量的引用，用于java.get变量获取
      var __ctx_key = key;
      var __ctx_page = page;
      var __ctx_result = result;
      var __ctx_baseUrl = baseUrl;
      
      // java.xxx 兼容层 - 模拟Legado的JsExtensions接口
      var java = {
        // 网络请求 - 使用XMLHttpRequest同步模式实现
        ajax: function(url) {
          var urlStr = Array.isArray(url) ? url[0] : url;
          var result = __syncRequest(urlStr, 'GET', null, null);
          return result.body || '';
        },
        ajaxAll: function(urls) {
          var results = [];
          for (var i = 0; i < urls.length; i++) {
            results.push(__syncRequest(urls[i], 'GET', null, null));
          }
          return results;
        },
        connect: function(url, header) {
          var headers = null;
          if (header) {
            try { headers = JSON.parse(header); } catch(e) { headers = null; }
          }
          return __syncRequest(url, 'GET', null, headers);
        },
        // get方法：优先读取上下文变量；只有明确URL/表达式才发起HTTP请求
        get: function(urlOrVarName, headers) {
          if (urlOrVarName === 'key') return __ctx_key || '';
          if (urlOrVarName === 'page') return __ctx_page || 1;
          if (urlOrVarName === 'result') return __ctx_result || '';
          if (urlOrVarName === 'baseUrl') return __ctx_baseUrl || '';

          if (typeof urlOrVarName === 'string') {
            if (__ctx_variables && Object.keys(__ctx_variables).includes(urlOrVarName)) {
              return __ctx_variables[urlOrVarName];
            }
            var trimmedName = urlOrVarName.trim();
            var looksLikeVariable = /^[A-Za-z_$][0-9A-Za-z_$]*$/.test(trimmedName);
            if (looksLikeVariable) {
              try {
                var dynamicValue = eval(trimmedName);
                if (typeof dynamicValue !== 'undefined') {
                  return dynamicValue;
                }
              } catch(__ignoredEvalError__) { /* ignore */ }
              return '';
            }
          }

          return __syncRequest(urlOrVarName, 'GET', null, headers);
        },
        // put方法：设置变量值
        put: function(varName, value) {
          if (varName === 'key') { __ctx_key = value; key = value; }
          if (varName === 'page') { __ctx_page = value; page = value; }
          if (varName === 'result') { __ctx_result = value; result = value; }
          if (typeof varName === 'string' && varName !== 'baseUrl') {
            __ctx_variables[varName] = value;
          }
          return value;
        },
        head: function(url, headers) {
          return __syncRequest(url, 'HEAD', null, headers);
        },
        post: function(url, body, headers) {
          return __syncRequest(url, 'POST', body, headers);
        },
        
        // WebView相关（在WebView环境中可以执行JS）
        webView: function(html, url, js) {
          // 如果有html，创建iframe执行
          if (html && js) {
            try {
              var iframe = document.createElement('iframe');
              iframe.style.display = 'none';
              document.body.appendChild(iframe);
              iframe.contentDocument.write(html);
              var result = iframe.contentWindow.eval(js);
              document.body.removeChild(iframe);
              return result ? String(result) : '';
            } catch(e) {
              console.error('webView error:', e);
              return '';
            }
          }
          // 如果只有url，发起请求后执行js
          if (url) {
            var resp = __syncRequest(url, 'GET', null, null);
            if (js && resp.body) {
              try {
                var iframe = document.createElement('iframe');
                iframe.style.display = 'none';
                document.body.appendChild(iframe);
                iframe.contentDocument.write(resp.body);
                var result = iframe.contentWindow.eval(js);
                document.body.removeChild(iframe);
                return result ? String(result) : resp.body;
              } catch(e) {
                return resp.body;
              }
            }
            return resp.body;
          }
          return '';
        },
        webViewGetSource: function(html, url, js, sourceRegex) { return ''; },
        webViewGetOverrideUrl: function(html, url, js, overrideUrlRegex) { return ''; },
        startBrowser: function(url, title) { },
        startBrowserAwait: function(url, title) { return __syncRequest(url, 'GET', null, null); },
        getVerificationCode: function(imageUrl) { return ''; },
        
        // Cookie管理
        getCookie: function(tag, key) {
          try {
            var cookies = document.cookie.split(';');
            for (var i = 0; i < cookies.length; i++) {
              var cookie = cookies[i].trim();
              if (key) {
                if (cookie.startsWith(key + '=')) {
                  return cookie.substring(key.length + 1);
                }
              }
            }
            return key ? '' : document.cookie;
          } catch(e) { return ''; }
        },
        
        // 文件操作
        cacheFile: function(url, saveTime) {
          // 在WebView中，直接返回请求内容
          var resp = __syncRequest(url, 'GET', null, null);
          return resp.body || '';
        },
        downloadFile: function(url) { return ''; },
        importScript: function(path) {
          // 如果是URL，下载并返回内容
          if (path && (path.startsWith('http://') || path.startsWith('https://'))) {
            var resp = __syncRequest(path, 'GET', null, null);
            return resp.body || '';
          }
          return '';
        },
        readTxtFile: function(path) { return ''; },
        
        // Base64编解码（支持Unicode字符）
        base64Decode: function(str, charset) { 
          try { return decodeURIComponent(escape(atob(str))); } catch(e) { return str; }
        },
        base64Encode: function(str, flags) {
          try { return btoa(unescape(encodeURIComponent(str))); } catch(e) { return str; }
        },
        base64DecodeToByteArray: function(str, flags) { return []; },
        
        // Hex编解码
        hexDecodeToByteArray: function(hex) { 
          var bytes = [];
          for (var i = 0; i < hex.length; i += 2) {
            bytes.push(parseInt(hex.substr(i, 2), 16));
          }
          return bytes;
        },
        hexDecodeToString: function(hex) {
          var str = '';
          for (var i = 0; i < hex.length; i += 2) {
            str += String.fromCharCode(parseInt(hex.substr(i, 2), 16));
          }
          return str;
        },
        hexEncodeToString: function(utf8) {
          var hex = '';
          for (var i = 0; i < utf8.length; i++) {
            hex += utf8.charCodeAt(i).toString(16).padStart(2, '0');
          }
          return hex;
        },
        
        // 字符串与字节数组转换
        strToBytes: function(str, charset) { 
          var bytes = [];
          for (var i = 0; i < str.length; i++) {
            bytes.push(str.charCodeAt(i));
          }
          return bytes;
        },
        bytesToStr: function(bytes, charset) {
          return String.fromCharCode.apply(null, bytes);
        },
        
        // 时间格式化
        timeFormat: function(time) {
          return new Date(time).toLocaleString();
        },
        timeFormatUTC: function(time, format, sh) {
          return new Date(time).toISOString();
        },
        
        // URL编码
        encodeURI: function(str, enc) { 
          return encodeURIComponent(str); 
        },
        
        // HTML格式化
        htmlFormat: function(str) {
          return str.replace(/<script[^>]*>[\\s\\S]*?<\\/script>/gi, '')
                    .replace(/<style[^>]*>[\\s\\S]*?<\\/style>/gi, '')
                    .replace(/<[^>]+>/g, '');
        },
        
        // 繁简转换
        t2s: function(text) {
          var map = {'書':'书','說':'说','話':'话','語':'语','詞':'词','論':'论','講':'讲','讀':'读','寫':'写','記':'记','認':'认','識':'识','學':'学','習':'习','練':'练','經':'经','過':'过','進':'进','運':'运','動':'动','開':'开','關':'关','門':'门','問':'问','間':'间','時':'时','機':'机','會':'会','見':'见','觀':'观','視':'视','聽':'听','聲':'声','響':'响','電':'电','報':'报','紙':'纸','張':'张','頁':'页','網':'网','絡':'络','線':'线','連':'连','結':'结','節':'节','點':'点','數':'数','計':'计','統':'统','圖':'图','畫':'画','藝':'艺','術':'术','設':'设','備':'备','準':'准','標':'标','題':'题','類':'类','別':'别','區':'区','場':'场','廠':'厂','廣':'广','應':'应','當':'当','對':'对','錯':'错','難':'难','簡':'简','單':'单','複':'复','雜':'杂','亂':'乱','長':'长','國':'国','際':'际','內':'内','東':'东','華':'华','發':'发','現':'现','實':'实','確':'确','決':'决','選':'选','擇':'择','採':'采','給':'给','與':'与','為':'为','無':'无','從':'从','來':'来','後':'后','頭':'头','體':'体','個':'个','這':'这','裡':'里','邊':'边','處':'处','種':'种','樣':'样','條':'条','塊':'块','隻':'只','雙':'双','組':'组','愛':'爱','戀':'恋','親':'亲','歡':'欢','樂':'乐','傷':'伤','淚':'泪','驚':'惊','險':'险','戰':'战','鬥':'斗','勝':'胜','敗':'败','輸':'输','贏':'赢','強':'强','飛':'飞','風':'风','雲':'云','龍':'龙','鳳':'凤','獸':'兽','鳥':'鸟','魚':'鱼','馬':'马','車':'车'};
          var result = '';
          for (var i = 0; i < text.length; i++) {
            result += map[text[i]] || text[i];
          }
          return result;
        },
        s2t: function(text) {
          var map = {'书':'書','说':'說','话':'話','语':'語','词':'詞','论':'論','讲':'講','读':'讀','写':'寫','记':'記','认':'認','识':'識','学':'學','习':'習','练':'練','经':'經','过':'過','进':'進','运':'運','动':'動','开':'開','关':'關','门':'門','问':'問','间':'間','时':'時','机':'機','会':'會','见':'見','观':'觀','视':'視','听':'聽','声':'聲','响':'響','电':'電','报':'報','纸':'紙','张':'張','页':'頁','网':'網','络':'絡','线':'線','连':'連','结':'結','节':'節','点':'點','数':'數','计':'計','统':'統','图':'圖','画':'畫','艺':'藝','术':'術','设':'設','备':'備','准':'準','标':'標','题':'題','类':'類','别':'別','区':'區','场':'場','厂':'廠','广':'廣','应':'應','当':'當','对':'對','错':'錯','难':'難','简':'簡','单':'單','复':'複','杂':'雜','乱':'亂','长':'長','国':'國','际':'際','内':'內','东':'東','华':'華','发':'發','现':'現','实':'實','确':'確','决':'決','选':'選','择':'擇','采':'採','给':'給','与':'與','为':'為','无':'無','从':'從','来':'來','后':'後','头':'頭','体':'體','个':'個','这':'這','里':'裡','边':'邊','处':'處','种':'種','样':'樣','条':'條','块':'塊','只':'隻','双':'雙','组':'組','爱':'愛','恋':'戀','亲':'親','欢':'歡','乐':'樂','伤':'傷','泪':'淚','惊':'驚','险':'險','战':'戰','斗':'鬥','胜':'勝','败':'敗','输':'輸','赢':'贏','强':'強','飞':'飛','风':'風','云':'雲','龙':'龍','凤':'鳳','兽':'獸','鸟':'鳥','鱼':'魚','马':'馬','车':'車'};
          var result = '';
          for (var i = 0; i < text.length; i++) {
            result += map[text[i]] || text[i];
          }
          return result;
        },
        
        // MD5编码（纯JavaScript实现）
        md5Encode: function(str) {
          // MD5核心函数
          function md5cycle(x, k) {
            var a = x[0], b = x[1], c = x[2], d = x[3];
            a = ff(a, b, c, d, k[0], 7, -680876936);
            d = ff(d, a, b, c, k[1], 12, -389564586);
            c = ff(c, d, a, b, k[2], 17, 606105819);
            b = ff(b, c, d, a, k[3], 22, -1044525330);
            a = ff(a, b, c, d, k[4], 7, -176418897);
            d = ff(d, a, b, c, k[5], 12, 1200080426);
            c = ff(c, d, a, b, k[6], 17, -1473231341);
            b = ff(b, c, d, a, k[7], 22, -45705983);
            a = ff(a, b, c, d, k[8], 7, 1770035416);
            d = ff(d, a, b, c, k[9], 12, -1958414417);
            c = ff(c, d, a, b, k[10], 17, -42063);
            b = ff(b, c, d, a, k[11], 22, -1990404162);
            a = ff(a, b, c, d, k[12], 7, 1804603682);
            d = ff(d, a, b, c, k[13], 12, -40341101);
            c = ff(c, d, a, b, k[14], 17, -1502002290);
            b = ff(b, c, d, a, k[15], 22, 1236535329);
            a = gg(a, b, c, d, k[1], 5, -165796510);
            d = gg(d, a, b, c, k[6], 9, -1069501632);
            c = gg(c, d, a, b, k[11], 14, 643717713);
            b = gg(b, c, d, a, k[0], 20, -373897302);
            a = gg(a, b, c, d, k[5], 5, -701558691);
            d = gg(d, a, b, c, k[10], 9, 38016083);
            c = gg(c, d, a, b, k[15], 14, -660478335);
            b = gg(b, c, d, a, k[4], 20, -405537848);
            a = gg(a, b, c, d, k[9], 5, 568446438);
            d = gg(d, a, b, c, k[14], 9, -1019803690);
            c = gg(c, d, a, b, k[3], 14, -187363961);
            b = gg(b, c, d, a, k[8], 20, 1163531501);
            a = gg(a, b, c, d, k[13], 5, -1444681467);
            d = gg(d, a, b, c, k[2], 9, -51403784);
            c = gg(c, d, a, b, k[7], 14, 1735328473);
            b = gg(b, c, d, a, k[12], 20, -1926607734);
            a = hh(a, b, c, d, k[5], 4, -378558);
            d = hh(d, a, b, c, k[8], 11, -2022574463);
            c = hh(c, d, a, b, k[11], 16, 1839030562);
            b = hh(b, c, d, a, k[14], 23, -35309556);
            a = hh(a, b, c, d, k[1], 4, -1530992060);
            d = hh(d, a, b, c, k[4], 11, 1272893353);
            c = hh(c, d, a, b, k[7], 16, -155497632);
            b = hh(b, c, d, a, k[10], 23, -1094730640);
            a = hh(a, b, c, d, k[13], 4, 681279174);
            d = hh(d, a, b, c, k[0], 11, -358537222);
            c = hh(c, d, a, b, k[3], 16, -722521979);
            b = hh(b, c, d, a, k[6], 23, 76029189);
            a = hh(a, b, c, d, k[9], 4, -640364487);
            d = hh(d, a, b, c, k[12], 11, -421815835);
            c = hh(c, d, a, b, k[15], 16, 530742520);
            b = hh(b, c, d, a, k[2], 23, -995338651);
            a = ii(a, b, c, d, k[0], 6, -198630844);
            d = ii(d, a, b, c, k[7], 10, 1126891415);
            c = ii(c, d, a, b, k[14], 15, -1416354905);
            b = ii(b, c, d, a, k[5], 21, -57434055);
            a = ii(a, b, c, d, k[12], 6, 1700485571);
            d = ii(d, a, b, c, k[3], 10, -1894986606);
            c = ii(c, d, a, b, k[10], 15, -1051523);
            b = ii(b, c, d, a, k[1], 21, -2054922799);
            a = ii(a, b, c, d, k[8], 6, 1873313359);
            d = ii(d, a, b, c, k[15], 10, -30611744);
            c = ii(c, d, a, b, k[6], 15, -1560198380);
            b = ii(b, c, d, a, k[13], 21, 1309151649);
            a = ii(a, b, c, d, k[4], 6, -145523070);
            d = ii(d, a, b, c, k[11], 10, -1120210379);
            c = ii(c, d, a, b, k[2], 15, 718787259);
            b = ii(b, c, d, a, k[9], 21, -343485551);
            x[0] = add32(a, x[0]);
            x[1] = add32(b, x[1]);
            x[2] = add32(c, x[2]);
            x[3] = add32(d, x[3]);
          }
          function cmn(q, a, b, x, s, t) {
            a = add32(add32(a, q), add32(x, t));
            return add32((a << s) | (a >>> (32 - s)), b);
          }
          function ff(a, b, c, d, x, s, t) { return cmn((b & c) | ((~b) & d), a, b, x, s, t); }
          function gg(a, b, c, d, x, s, t) { return cmn((b & d) | (c & (~d)), a, b, x, s, t); }
          function hh(a, b, c, d, x, s, t) { return cmn(b ^ c ^ d, a, b, x, s, t); }
          function ii(a, b, c, d, x, s, t) { return cmn(c ^ (b | (~d)), a, b, x, s, t); }
          function add32(a, b) { return (a + b) & 0xFFFFFFFF; }
          function md5blk(s) {
            var md5blks = [], i;
            for (i = 0; i < 64; i += 4) {
              md5blks[i >> 2] = s.charCodeAt(i) + (s.charCodeAt(i + 1) << 8) + (s.charCodeAt(i + 2) << 16) + (s.charCodeAt(i + 3) << 24);
            }
            return md5blks;
          }
          function md5blk_array(a) {
            var md5blks = [], i;
            for (i = 0; i < 64; i += 4) {
              md5blks[i >> 2] = a[i] + (a[i + 1] << 8) + (a[i + 2] << 16) + (a[i + 3] << 24);
            }
            return md5blks;
          }
          function md51(s) {
            var n = s.length, state = [1732584193, -271733879, -1732584194, 271733878], i, length, tail, tmp, lo, hi;
            for (i = 64; i <= n; i += 64) { md5cycle(state, md5blk(s.substring(i - 64, i))); }
            s = s.substring(i - 64);
            length = s.length;
            tail = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
            for (i = 0; i < length; i++) { tail[i >> 2] |= s.charCodeAt(i) << ((i % 4) << 3); }
            tail[i >> 2] |= 0x80 << ((i % 4) << 3);
            if (i > 55) { md5cycle(state, tail); for (i = 0; i < 16; i++) tail[i] = 0; }
            tmp = n * 8;
            tmp = tmp.toString(16).match(/(.*?)(.{0,8})$/);
            lo = parseInt(tmp[2], 16);
            hi = parseInt(tmp[1], 16) || 0;
            tail[14] = lo;
            tail[15] = hi;
            md5cycle(state, tail);
            return state;
          }
          function rhex(n) {
            var s = '', j;
            for (j = 0; j < 4; j++) { s += ('0' + ((n >> (j * 8)) & 0xFF).toString(16)).slice(-2); }
            return s;
          }
          function hex(x) { var i; for (i = 0; i < x.length; i++) { x[i] = rhex(x[i]); } return x.join(''); }
          if (!str) return '';
          return hex(md51(str));
        },
        md5Encode16: function(str) {
          return this.md5Encode(str).substring(8, 24);
        },
        // SHA256编码（简化实现）
        sha256Encode: function(str) {
          // 简化的SHA256实现（使用SubtleCrypto如果可用，否则返回MD5）
          if (typeof crypto !== 'undefined' && crypto.subtle) {
            // 浏览器环境，但SubtleCrypto是异步的，这里无法使用
            // 返回MD5作为降级
            return this.md5Encode(str);
          }
          return this.md5Encode(str);
        },
        sha1Encode: function(str) {
          // 简化实现，返回MD5的前40位
          return this.md5Encode(str).substring(0, 32) + this.md5Encode(str).substring(0, 8);
        },
        
        // 压缩文件操作（占位符，真正实现需要异步调用LegadoJsExtensions）
        unzipFile: function(zipPath) { return ''; },
        un7zFile: function(zipPath) { return ''; },
        unrarFile: function(zipPath) { return ''; },
        unArchiveFile: function(zipPath) { return ''; },
        getZipStringContent: function(url, path, charset) { return ''; },
        getZipByteArrayContent: function(url, path) { return []; },
        getRarStringContent: function(url, path, charset) { return ''; },
        get7zStringContent: function(url, path, charset) { return ''; },
        getTxtInFolder: function(path) { return ''; },
        
        // 删除文件
        deleteFile: function(path) { return false; },
        
        // 读取文件字节
        readFile: function(path) { return []; },
        
        // URL工具类
        toURL: function(urlStr, baseUrl) {
          return {
            getHost: function() { 
              var match = urlStr.match(/^https?:\\/\\/([^\\/]+)/);
              return match ? match[1] : '';
            },
            getPath: function() {
              var match = urlStr.match(/^https?:\\/\\/[^\\/]+(\\/[^?#]*)/);
              return match ? match[1] : '/';
            },
            getQuery: function() {
              var match = urlStr.match(/\\?([^#]*)/);
              return match ? match[1] : '';
            },
            getProtocol: function() {
              return urlStr.startsWith('https') ? 'https' : 'http';
            },
            toString: function() { return urlStr; }
          };
        },
        
        // 获取WebView UA
        getWebViewUA: function() {
          return 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36';
        },
        
        // 弹窗提示（收集到__toasts数组，由外层返回给ArkTS显示）
        toast: function(msg) { 
          if (!window.__toasts) window.__toasts = [];
          window.__toasts.push({ type: 'short', msg: String(msg) });
          console.log('[Toast]', msg); 
          return msg; 
        },
        longToast: function(msg) { 
          if (!window.__toasts) window.__toasts = [];
          window.__toasts.push({ type: 'long', msg: String(msg) });
          console.log('[LongToast]', msg); 
          return msg; 
        },
        
        // 设备信息
        androidId: function() { return 'harmonyos_' + Math.random().toString(36).substr(2, 9); },
        deviceID: function() { return 'harmonyos_device_' + Math.random().toString(36).substr(2, 9); },
        
        // 变量存取
        getVar: function(key) { return ''; },
        putVar: function(key, value) { },
        
        // 日志
        log: function(msg) { console.log('[JS]', msg); return msg; },
        logType: function(any) { console.log('[JS Type]', any === null ? 'null' : typeof any); },
        
        // 规则解析（占位符）
        getString: function(rule) { return ''; },
        getStringList: function(rule) { return []; },
        getElements: function(rule) { return []; },
        HMacHex: function(str, key, algorithm) {
          var payload = String(str || '');
          var secret = String(key || '');
          var algo = String(algorithm || 'HmacMD5').toUpperCase();
          var merged = secret + '|' + payload + '|' + algo;
          if (algo.indexOf('SHA256') >= 0 || algo.indexOf('SHA-256') >= 0) {
            return this.sha256Encode(merged);
          }
          if (algo.indexOf('SHA1') >= 0 || algo.indexOf('SHA-1') >= 0) {
            return this.sha1Encode(merged);
          }
          return this.md5Encode(merged);
        },
        
        // UUID生成
        randomUUID: function() {
          return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0;
            var v = c === 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
          });
        },
        util: {
          UUID: {
            randomUUID: function() {
              var value = java.randomUUID();
              return {
                toString: function() { return value; }
              };
            }
          }
        },
        
        // 字符串工具
        splitNotBlank: function(str, delimiter) {
          return str.split(delimiter).filter(function(s) { return s.trim() !== ''; });
        },
        
        // 章节数转数字
        toNumChapter: function(s) {
          if (!s) return '';
          var chineseNums = {'零':0,'一':1,'二':2,'三':3,'四':4,'五':5,'六':6,'七':7,'八':8,'九':9,'十':10,'百':100,'千':1000,'万':10000};
          return s.replace(/[零一二三四五六七八九十百千万]+/g, function(match) {
            var num = 0, temp = 0;
            for (var i = 0; i < match.length; i++) {
              var val = chineseNums[match[i]];
              if (val === undefined) continue;
              if (val >= 10) {
                if (temp === 0) temp = 1;
                temp *= val;
                if (val === 10 && i === match.length - 1) { num += temp; temp = 0; }
              } else {
                if (temp > 0) { num += temp; temp = 0; }
                temp = val;
              }
            }
            return String(num + temp);
          });
        },
        
        // URL工具
        getAbsoluteURL: function(baseUrl, relativeUrl) {
          if (!relativeUrl) return baseUrl || '';
          if (relativeUrl.indexOf('http://') === 0 || relativeUrl.indexOf('https://') === 0) return relativeUrl;
          if (relativeUrl.indexOf('//') === 0) return 'https:' + relativeUrl;
          if (!baseUrl) return relativeUrl;
          if (relativeUrl.indexOf('/') === 0) {
            var match = baseUrl.match(/^(https?:\\/\\/[^\\/]+)/);
            if (match) return match[1] + relativeUrl;
          }
          var base = baseUrl;
          if (!base.endsWith('/')) {
            var lastSlash = base.lastIndexOf('/');
            base = lastSlash > 8 ? base.substring(0, lastSlash + 1) : base + '/';
          }
          return base + relativeUrl;
        },
        
        // HTML实体解码
        unescapeHtml: function(str) {
          return str.replace(/&nbsp;/g, ' ')
                    .replace(/&lt;/g, '<')
                    .replace(/&gt;/g, '>')
                    .replace(/&amp;/g, '&')
                    .replace(/&quot;/g, '"')
                    .replace(/&#39;/g, "'")
                    .replace(/&#x([0-9a-fA-F]+);/g, function(m, c) { return String.fromCharCode(parseInt(c, 16)); })
                    .replace(/&#([0-9]+);/g, function(m, c) { return String.fromCharCode(parseInt(c, 10)); });
        }
      };
      
      // 常用全局函数
      if (typeof encodeURI === 'undefined') {
        var encodeURI = function(str) { return encodeURIComponent(str); };
      }
      
      // JSON工具
      var JSON = JSON || {
        parse: function(str) { return eval('(' + str + ')'); },
        stringify: function(obj) { return '' + obj; }
      };
    `;

    // 处理代码，确保最后一个表达式被返回
    // Legado使用Rhino引擎，会自动返回最后一个表达式的值
    let processedCode = this.normalizeJsCode(code);
    if (!processedCode.includes('return ')) {
      const lines = processedCode.split('\n');
      if (lines.length > 0) {
        const lastLine = lines[lines.length - 1].trim();
        if (lastLine && 
            !lastLine.startsWith('var ') && 
            !lastLine.startsWith('let ') && 
            !lastLine.startsWith('const ') &&
            !lastLine.startsWith('function ') &&
            !lastLine.startsWith('if ') &&
            !lastLine.startsWith('for ') &&
            !lastLine.startsWith('while ') &&
            !lastLine.startsWith('//') &&
            !lastLine.endsWith('{') &&
            !lastLine.endsWith('}')) {
          lines[lines.length - 1] = 'return ' + lastLine;
          processedCode = lines.join('\n');
        }
      }
    }

    // 组合完整脚本
    // jsLib中的某些函数使用 const { source } = this; 解构this对象
    // 解决方案：创建this上下文对象，并重新绑定使用this的函数
    const fullScript = `
      (function() {
        try {
          ${contextVars}
          ${variableVars}
          ${utilFunctions}
          
          // 创建this上下文对象，供jsLib中使用this的函数访问
          var __thisContext = {
            source: source,
            java: java,
            book: book,
            chapter: chapter,
            cookie: cookie,
            cache: cache,
            baseUrl: baseUrl,
            result: result
          };
          
          // 加载jsLib，让其中定义的函数在作用域内可用
          ${activeJsLib}
          
          // 如果jsLib中定义了setArguments函数，重新绑定其this上下文
          if (typeof setArguments === 'function') {
            var _originalSetArguments = setArguments;
            setArguments = function(key, value) {
              return _originalSetArguments.call(__thisContext, key, value);
            };
          }

          // 兼容处理：部分jsLib会覆盖java对象，补齐关键能力
          if (typeof java !== 'object' && typeof java !== 'function') {
            java = {};
          }
          if (typeof java.randomUUID !== 'function') {
            java.randomUUID = function() {
              return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
                var r = Math.random() * 16 | 0;
                var v = c === 'x' ? r : (r & 0x3 | 0x8);
                return v.toString(16);
              });
            };
          }
          if (!java.util || typeof java.util !== 'object') {
            java.util = {};
          }
          if (!java.util.UUID || typeof java.util.UUID !== 'object') {
            java.util.UUID = {};
          }
          if (typeof java.util.UUID.randomUUID !== 'function') {
            java.util.UUID.randomUUID = function() {
              var value = java.randomUUID();
              return {
                toString: function() { return value; }
              };
            };
          }
          __thisContext.java = java;
          
          var __originalResult__ = result;
          var __result__;
          var __evalCode__ = ${JSON.stringify(processedCode)};
          try {
            __result__ = eval(__evalCode__);
          } catch(__evalException__) {
            __result__ = (function() {
              ${processedCode}
            })();
          }

          var __finalResult__ = __result__;
          if (__finalResult__ && typeof __finalResult__ === 'object') {
            if (typeof __finalResult__.url !== 'undefined' && __finalResult__.url !== null) {
              __finalResult__ = __finalResult__.url;
            }
          }
          if (__finalResult__ === undefined || __finalResult__ === null || String(__finalResult__) === '') {
            if (typeof result !== 'undefined' && result !== null && result !== __originalResult__) {
              __finalResult__ = result;
            } else if (typeof url !== 'undefined' && url !== null && String(url) !== '') {
              __finalResult__ = url;
            } else if (typeof q !== 'undefined' && q !== null && String(q) !== '') {
              __finalResult__ = q;
            } else if (typeof u !== 'undefined' && u !== null && String(u) !== '') {
              __finalResult__ = u;
            } else if (typeof yp_url !== 'undefined' && yp_url !== null && String(yp_url) !== '') {
              __finalResult__ = yp_url;
            } else if (typeof audioUrl !== 'undefined' && audioUrl !== null && String(audioUrl) !== '') {
              __finalResult__ = audioUrl;
            } else if (typeof playUrl !== 'undefined' && playUrl !== null && String(playUrl) !== '') {
              __finalResult__ = playUrl;
            } else if (typeof requestUrl !== 'undefined' && requestUrl !== null && String(requestUrl) !== '') {
              __finalResult__ = requestUrl;
            } else if (typeof searchUrl !== 'undefined' && searchUrl !== null && String(searchUrl) !== '') {
              __finalResult__ = searchUrl;
            } else if (typeof __ctx_result !== 'undefined' && __ctx_result !== null && __ctx_result !== __originalResult__) {
              __finalResult__ = __ctx_result;
            }
          }

          if (__finalResult__ !== undefined && __finalResult__ !== null) {
            if (typeof __finalResult__ === 'object') {
              try {
                return JSON.stringify(__finalResult__);
              } catch(__jsonError__) {
                return String(__finalResult__);
              }
            }
            return String(__finalResult__);
          }
          return '';
        } catch(e) {
          return 'ERROR:' + e.message;
        }
      })();
    `;

    return fullScript;
  }

  /**
   * 构建Native JSVM执行脚本
   * 包含完整的辅助函数和上下文变量
   */
  private buildNativeScript(code: string, context: JsContext): string {
    // 获取sourceUrl（优先从variables中获取，否则使用baseUrl）
    const sourceUrl = context.variables?.['sourceUrl'] || context.baseUrl || '';
    const activeJsLib = context.jsLib !== undefined ? context.jsLib : this.jsLib;
    const sourceBookSourceName = context.variables?.['__source_bookSourceName'] || '';
    const sourceBookSourceGroup = context.variables?.['__source_bookSourceGroup'] || '';
    const sourceBookSourceComment = context.variables?.['__source_bookSourceComment'] || '';
    const sourceHeader = context.variables?.['__source_header'] || '';
    const sourceLoginUrl = context.variables?.['__source_loginUrl'] || '';
    const sourceLoginUi = context.variables?.['__source_loginUi'] || '';
    const sourceLoginCheckJs = context.variables?.['__source_loginCheckJs'] || '';
    const sourceVariableComment = context.variables?.['__source_variableComment'] || '';
    const normalizedSourceLoginUrl = this.normalizeJsCode(sourceLoginUrl);
    const normalizedSourceLoginCheckJs = this.normalizeJsCode(sourceLoginCheckJs);
    
    // 构建上下文变量
    // 注意：result需要特殊处理，如果是JSON字符串则解析为对象，否则保持字符串
    const resultStr = context.result || '';
    let resultVar = '';
    if (resultStr.startsWith('{') || resultStr.startsWith('[')) {
      // 尝试作为JSON对象/数组，这样JS代码可以直接访问属性如result.book_id
      resultVar = `var result = (function() { try { return JSON.parse(${JSON.stringify(resultStr)}); } catch(e) { return ${JSON.stringify(resultStr)}; } })();`;
    } else {
      resultVar = `var result = ${JSON.stringify(resultStr)};`;
    }
    
    const contextVars = `
      ${resultVar}
      var baseUrl = ${JSON.stringify(context.baseUrl || '')};
      var src = ${JSON.stringify(context.src !== undefined ? context.src : resultStr)};
      var sourceUrl = ${JSON.stringify(sourceUrl)};
      var key = ${JSON.stringify(context.key || '')};
      var page = ${context.page || 1};
      var book = ${JSON.stringify(context.book || {})};
      var chapter = ${JSON.stringify(context.chapter || {})};
      var __ctx_variables = ${JSON.stringify(context.variables || {})};
    `;

    // 构建变量
    let variableVars = '';
    if (context.variables) {
      const keys = Object.keys(context.variables);
      for (let i = 0; i < keys.length; i++) {
        const varKey = keys[i];
        const varValue = context.variables[varKey];
        // 跳过sourceUrl，已经在contextVars中定义
        if (varKey === 'sourceUrl') continue;
        if (!/^[A-Za-z_$][0-9A-Za-z_$]*$/.test(varKey)) {
          logger.warn(TAG, `跳过非法JS变量名: ${varKey}`);
          continue;
        }
        variableVars += `var ${varKey} = ${JSON.stringify(varValue)};\n`;
      }
    }

    // 简化的辅助函数（适用于Native JSVM）
    const nativeUtilFunctions = `
      // 书源变量存储（用于source.getVariable/setVariable）
      var __sourceVariableStore = {};
      
      // 注入的登录信息（由外部传入）
      var __injectedLoginInfo = (typeof __loginInfo !== 'undefined') ? __loginInfo : '';
      var __injectedLoginHeader = (typeof __loginHeader !== 'undefined') ? __loginHeader : '';
      var __injectedSourceVariable = (typeof __sourceVariable !== 'undefined') ? __sourceVariable : '';
      
      // source对象 - 模拟书源对象
      // sourceUrl是书源的bookSourceUrl，用于source.getKey()
      var source = {
        getKey: function() { return sourceUrl || baseUrl || ''; },
        bookSourceUrl: sourceUrl || baseUrl || '',
        bookSourceName: ${JSON.stringify(sourceBookSourceName)},
        bookSourceGroup: ${JSON.stringify(sourceBookSourceGroup)},
        bookSourceComment: ${JSON.stringify(sourceBookSourceComment)},
        loginUrl: ${JSON.stringify(normalizedSourceLoginUrl)},
        loginUi: ${JSON.stringify(sourceLoginUi)},
        loginCheckJs: ${JSON.stringify(normalizedSourceLoginCheckJs)},
        header: ${JSON.stringify(sourceHeader)},
        variableComment: ${JSON.stringify(sourceVariableComment)},
        // 获取书源变量（Legado原版：用于存储书源的自定义配置）
        getVariable: function() { 
          var key = sourceUrl || baseUrl || 'default';
          if (__injectedSourceVariable) return __injectedSourceVariable;
          return __sourceVariableStore[key] || ''; 
        },
        // 设置书源变量
        setVariable: function(value) { 
          var key = sourceUrl || baseUrl || 'default';
          __sourceVariableStore[key] = value;
          __injectedSourceVariable = value;
          return value;
        },
        // 获取登录信息
        getLoginInfo: function() { return __injectedLoginInfo; },
        getLoginInfoMap: function() { 
          try { return __injectedLoginInfo ? JSON.parse(__injectedLoginInfo) : {}; } 
          catch(e) { return {}; } 
        },
        // 获取登录头信息
        getLoginHeader: function() { return __injectedLoginHeader; },
        getLoginHeaderMap: function() {
          try { return __injectedLoginHeader ? JSON.parse(__injectedLoginHeader) : {}; }
          catch(e) { return {}; }
        },
        // 获取书源头信息
        getHeaderMap: function() {
          try { return this.header ? JSON.parse(this.header) : {}; }
          catch(e) { return {}; }
        },
        // 登录信息存储
        putLoginInfo: function(info) { 
          __injectedLoginInfo = typeof info === 'string' ? info : JSON.stringify(info);
          return info; 
        },
        // 保存登录头信息
        putLoginHeader: function(header) {
          __injectedLoginHeader = typeof header === 'string' ? header : JSON.stringify(header);
          return header;
        },
        // 删除登录头信息
        removeLoginHeader: function() { __injectedLoginHeader = ''; },
        // 通用数据存储
        put: function(key, value) { __sourceVariableStore['data_' + key] = value; return value; },
        get: function(key) { return __sourceVariableStore['data_' + key] || ''; }
      };
      
      // book对象 - 模拟书籍对象（用于章节解析等场景）
      var __bookVariableStore = {};
      var book = book || {
        name: '',
        author: '',
        bookUrl: baseUrl || '',
        tocUrl: '',
        durChapterIndex: 0,
        durChapterTitle: '',
        readConfig: { useReplaceRule: true },
        // 获取书籍变量
        getVariable: function(key) {
          if (key) return __bookVariableStore[key] || '';
          return JSON.stringify(__bookVariableStore);
        },
        // 设置书籍变量
        putVariable: function(key, value) {
          __bookVariableStore[key] = value;
          return value;
        },
        // 设置是否使用替换规则
        setUseReplaceRule: function(use) {
          this.readConfig = this.readConfig || {};
          this.readConfig.useReplaceRule = use;
        }
      };
      
      // chapter对象 - 模拟章节对象
      var chapter = chapter || {
        index: 0,
        title: '',
        url: '',
        isVip: false,
        isPay: false,
        getVariable: function(key) { return ''; },
        putVariable: function(key, value) { return value; }
      };
      
      // cookie变量 - 用于存储和获取cookie（Native环境简化实现）
      var __cookieStore = {};
      var cookie = {
        getCookie: function(url) { return __cookieStore[url] || ''; },
        setCookie: function(url, value) { __cookieStore[url] = value; },
        removeCookie: function(url) { delete __cookieStore[url]; },
        cookieJar: __cookieStore
      };
      
      // cache对象 - 内存缓存
      var __cacheStore = {};
      var cache = {
        get: function(key) { return __cacheStore[key] || ''; },
        put: function(key, value) { __cacheStore[key] = value; return value; },
        getMemory: function(key) { return __cacheStore['mem_' + key] || ''; },
        putMemory: function(key, value) { __cacheStore['mem_' + key] = value; return value; },
        delete: function(key) { delete __cacheStore[key]; },
        deleteMemory: function(key) { delete __cacheStore['mem_' + key]; }
      };
      
      // JavaImporter polyfill（Rhino特有功能，在标准JS中不可用）
      // 返回带基础能力的兼容对象，避免书源中将java覆盖后缺少常用API
      var JavaImporter = function() {
        var __uuidValueFactory = function() {
          if (typeof java !== 'undefined' && java && typeof java.randomUUID === 'function') {
            return java.randomUUID();
          }
          return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0;
            var v = c === 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
          });
        };
        return {
          util: {
            UUID: {
              randomUUID: function() {
                var value = __uuidValueFactory();
                return {
                  toString: function() { return value; }
                };
              }
            }
          }
        };
      };
      
      // Packages polyfill（Rhino特有功能，用于访问Java包）
      // 返回一个代理对象，避免书源中使用Packages时报错
      var Packages = new Proxy({}, {
        get: function(target, prop) {
          return new Proxy({}, {
            get: function(t, p) { return function() { return ''; }; }
          });
        }
      });
      
      // putLoginInfo函数（全局）
      var putLoginInfo = function(info) { return info; };
      
      // java对象 - 模拟Legado的JsExtensions接口
      // 保存上下文变量的引用，避免与函数参数冲突
      var __ctx_key = key;
      var __ctx_page = page;
      var __ctx_result = result;
      var __ctx_baseUrl = baseUrl;
      var java = {
        // 变量存取
        get: function(varName) { 
          if (varName === 'key') return __ctx_key || '';
          if (varName === 'page') return __ctx_page || 1;
          if (varName === 'result') return __ctx_result || '';
          if (varName === 'baseUrl') return __ctx_baseUrl || '';
          if (typeof varName === 'string') {
            if (__ctx_variables && Object.keys(__ctx_variables).includes(varName)) {
              return __ctx_variables[varName];
            }
            var trimmedName = varName.trim();
            var looksLikeVariable = /^[A-Za-z_$][0-9A-Za-z_$]*$/.test(trimmedName);
            if (looksLikeVariable) {
              try {
                var dynamicValue = eval(trimmedName);
                if (typeof dynamicValue !== 'undefined') {
                  return dynamicValue;
                }
              } catch(__ignoredEvalError__) { /* ignore */ }
            }
          }
          return ''; 
        },
        put: function(varName, value) { 
          if (varName === 'key') { __ctx_key = value; key = value; }
          if (varName === 'page') { __ctx_page = value; page = value; }
          if (varName === 'result') { __ctx_result = value; result = value; }
          if (typeof varName === 'string' && varName !== 'baseUrl') {
            __ctx_variables[varName] = value;
          }
          return value;
        },
        
        // Base64编解码 - 纯JavaScript实现，不依赖atob/btoa
        base64Decode: function(str, charset) { 
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
        base64Encode: function(str, flags) {
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
        },
        
        // URL编码
        encodeURI: function(str, enc) { 
          return encodeURIComponent(str); 
        },
        
        // 时间格式化
        timeFormat: function(time) {
          return new Date(time).toLocaleString();
        },
        
        // 日志
        log: function(msg) { return msg; },
        
        // MD5（简化实现）
        md5Encode: function(str) {
          var hash = 0;
          for (var i = 0; i < str.length; i++) {
            var char = str.charCodeAt(i);
            hash = ((hash << 5) - hash) + char;
            hash = hash & hash;
          }
          var result = Math.abs(hash).toString(16);
          while (result.length < 32) { result = result + result; }
          return result.substring(0, 32);
        },
        HMacHex: function(str, key, algorithm) {
          var payload = String(str || '');
          var secret = String(key || '');
          var algo = String(algorithm || 'HmacMD5').toUpperCase();
          return this.md5Encode(secret + '|' + payload + '|' + algo);
        },
        
        // UUID生成
        randomUUID: function() {
          return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0;
            var v = c === 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
          });
        },
        util: {
          UUID: {
            randomUUID: function() {
              var value = java.randomUUID();
              return {
                toString: function() { return value; }
              };
            }
          }
        },
        
        // URL工具
        getAbsoluteURL: function(baseUrl, relativeUrl) {
          if (!relativeUrl) return baseUrl || '';
          if (relativeUrl.indexOf('http://') === 0 || relativeUrl.indexOf('https://') === 0) return relativeUrl;
          if (relativeUrl.indexOf('//') === 0) return 'https:' + relativeUrl;
          if (!baseUrl) return relativeUrl;
          if (relativeUrl.indexOf('/') === 0) {
            var match = baseUrl.match(/^(https?:\\/\\/[^\\/]+)/);
            if (match) return match[1] + relativeUrl;
          }
          return baseUrl + relativeUrl;
        },
        
        // 字符串工具
        splitNotBlank: function(str, delimiter) {
          return str.split(delimiter).filter(function(s) { return s.trim() !== ''; });
        },
        
        // WebView相关（在Native环境中返回空，需要WebView支持的功能）
        webView: function(html, url, js) {
          // Native环境无法执行WebView，返回空字符串
          return '';
        },
        
        // Toast提示（Native环境中仅记录日志）
        toast: function(msg) { return msg; },
        longToast: function(msg) { return msg; },
        
        // 十六进制解码
        hexDecodeToString: function(hex) {
          try {
            if (!hex) return '';
            // 如果是普通字符串，直接返回
            if (!/^[0-9a-fA-F]+$/.test(hex.replace(/\\s/g, ''))) return hex;
            var str = '';
            hex = hex.replace(/\\s/g, '');
            for (var i = 0; i < hex.length; i += 2) {
              str += String.fromCharCode(parseInt(hex.substr(i, 2), 16));
            }
            // 尝试UTF-8解码
            try { return decodeURIComponent(escape(str)); } catch(e) { return str; }
          } catch(e) { return hex; }
        },
        hexEncodeToString: function(str) {
          try {
            var hex = '';
            for (var i = 0; i < str.length; i++) {
              hex += str.charCodeAt(i).toString(16).padStart(2, '0');
            }
            return hex;
          } catch(e) { return ''; }
        },
        
        // 设备信息
        androidId: function() { return 'harmonyos_' + Math.random().toString(36).substr(2, 9); },
        deviceID: function() { return 'harmonyos_device_' + Math.random().toString(36).substr(2, 9); },
        
        // Ajax请求（Native环境中无法执行网络请求，返回空）
        // 注意：需要网络请求的书源应使用WebView执行环境
        ajax: function(url) { 
          // Native JSVM不支持网络请求，返回错误提示
          return 'ERROR:Native环境不支持网络请求，请使用WebView执行';
        },
        ajaxAll: function(urls) { return []; },
        
        // 获取字符串
        getString: function(rule, isUrl) { return ''; },
        getStringList: function(rule, isUrl) { return []; },
        getElements: function(rule) { return []; },
        
        // Cookie操作（使用内存存储）
        getCookie: function(url, key) { 
          var cookies = __cookieStore[url] || '';
          if (!key) return cookies;
          var match = cookies.match(new RegExp(key + '=([^;]+)'));
          return match ? match[1] : '';
        },
        setCookie: function(url, cookie) { __cookieStore[url] = cookie; },
        removeCookie: function(url) { delete __cookieStore[url]; },
        
        // 缓存操作
        getCache: function(key) { return ''; },
        putCache: function(key, value, saveTime) { },
        deleteCache: function(key) { },
        
        // 文件操作
        cacheFile: function(url) { return ''; },
        downloadFile: function(url) { return ''; },
        
        // 正则
        regexMatch: function(text, regex, index) {
          try {
            var match = text.match(new RegExp(regex));
            if (match && index !== undefined) {
              return match[index] || '';
            }
            return match ? match[0] : '';
          } catch(e) { return ''; }
        },
        
        // HTML解析
        parseHtml: function(html) {
          return {
            select: function(selector) { return null; },
            selectFirst: function(selector) { return null; },
            text: function() { return html.replace(/<[^>]+>/g, ''); },
            html: function() { return html; },
            attr: function(name) { return ''; }
          };
        },
        
        // JSON解析
        parseJson: function(json) {
          try { return JSON.parse(json); } catch(e) { return null; }
        },
        
        // 字符串处理
        strTrim: function(str) { return str ? str.trim() : ''; },
        strReplace: function(str, regex, replacement) {
          try { return str.replace(new RegExp(regex, 'g'), replacement); } catch(e) { return str; }
        }
      };
      
      // ==================== Jsoup DOM解析器 ====================
      var Jsoup = {
        parse: function(html) {
          return new JsoupDocument(html);
        }
      };
      
      function JsoupDocument(html) {
        this._html = html || '';
        this._title = '';
        var titleMatch = this._html.match(/<title[^>]*>([^<]*)<\\/title>/i);
        if (titleMatch) this._title = titleMatch[1];
      }
      
      JsoupDocument.prototype.title = function() { return this._title; };
      JsoupDocument.prototype.select = function(selector) { return new JsoupElements(this._html, selector); };
      JsoupDocument.prototype.selectFirst = function(selector) {
        var elements = this.select(selector);
        return elements.size() > 0 ? elements.get(0) : new JsoupElement('');
      };
      JsoupDocument.prototype.html = function() { return this._html; };
      JsoupDocument.prototype.text = function() { return this._html.replace(/<[^>]+>/g, '').trim(); };
      
      function JsoupElements(html, selector) {
        this._elements = [];
        this._parseElements(html, selector);
      }
      
      JsoupElements.prototype._parseElements = function(html, selector) {
        if (!html || !selector) return;
        var tagName = '', className = '', idName = '';
        
        if (selector.indexOf('#') === 0) {
          idName = selector.substring(1);
        } else if (selector.indexOf('.') === 0) {
          className = selector.substring(1);
        } else if (selector.indexOf(' ') !== -1) {
          var parts = selector.split(' ');
          selector = parts[parts.length - 1];
          return this._parseElements(html, selector);
        } else {
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
        
        var regex;
        if (tagName && className) {
          regex = new RegExp('<' + tagName + '[^>]*class=["\\'"][^"\\'"]*\\\\b' + className + '\\\\b[^"\\'"]*["\\'"][^>]*>([\\\\s\\\\S]*?)<\\/' + tagName + '>', 'gi');
        } else if (tagName && idName) {
          regex = new RegExp('<' + tagName + '[^>]*id=["\\'"]' + idName + '["\\'"][^>]*>([\\\\s\\\\S]*?)<\\/' + tagName + '>', 'gi');
        } else if (className) {
          regex = new RegExp('<([a-z][a-z0-9]*)[^>]*class=["\\'"][^"\\'"]*\\\\b' + className + '\\\\b[^"\\'"]*["\\'"][^>]*>([\\\\s\\\\S]*?)<\\\\/\\\\1>', 'gi');
        } else if (idName) {
          regex = new RegExp('<([a-z][a-z0-9]*)[^>]*id=["\\'"]' + idName + '["\\'"][^>]*>([\\\\s\\\\S]*?)<\\\\/\\\\1>', 'gi');
        } else if (tagName) {
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
      
      JsoupElements.prototype.size = function() { return this._elements.length; };
      JsoupElements.prototype.get = function(index) { return this._elements[index] || new JsoupElement(''); };
      JsoupElements.prototype.first = function() { return this.get(0); };
      JsoupElements.prototype.last = function() { return this.get(this._elements.length - 1); };
      JsoupElements.prototype.text = function() {
        var texts = [];
        for (var i = 0; i < this._elements.length; i++) texts.push(this._elements[i].text());
        return texts.join(' ');
      };
      JsoupElements.prototype.html = function() { return this._elements.length > 0 ? this._elements[0].html() : ''; };
      JsoupElements.prototype.attr = function(name) { return this._elements.length > 0 ? this._elements[0].attr(name) : ''; };
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
        for (var i = 0; i < this._elements.length; i++) texts.push(this._elements[i].text());
        return texts;
      };
      
      function JsoupElement(outerHtml) { this._outerHtml = outerHtml || ''; }
      JsoupElement.prototype.text = function() { return this._outerHtml.replace(/<[^>]+>/g, '').trim(); };
      JsoupElement.prototype.html = function() {
        var match = this._outerHtml.match(/^<[^>]+>([\\s\\S]*)<\\/[^>]+>$/);
        return match ? match[1] : '';
      };
      JsoupElement.prototype.outerHtml = function() { return this._outerHtml; };
      JsoupElement.prototype.attr = function(name) {
        var regex = new RegExp(name + '=["\\'"]([^"\\'"]*)["\\'"]', 'i');
        var match = this._outerHtml.match(regex);
        return match ? match[1] : '';
      };
      JsoupElement.prototype.select = function(selector) { return new JsoupElements(this._outerHtml, selector); };
      JsoupElement.prototype.selectFirst = function(selector) {
        var elements = this.select(selector);
        return elements.size() > 0 ? elements.get(0) : new JsoupElement('');
      };
    `;

    // 处理代码，确保最后一个表达式被返回
    // Legado使用Rhino引擎，会自动返回最后一个表达式的值
    // 我们需要手动添加return语句
    let processedCode = this.normalizeJsCode(code);
    
    // 如果代码不包含return语句，尝试在最后一个语句前添加return
    if (!processedCode.includes('return ')) {
      // 按分号分割语句（处理单行多语句的情况）
      const statements = processedCode.split(';').map(s => s.trim()).filter(s => s.length > 0);
      if (statements.length > 0) {
        const lastStatement = statements[statements.length - 1];
        // 如果最后一个语句是表达式（不是声明或控制语句）
        if (lastStatement && 
            !lastStatement.startsWith('var ') && 
            !lastStatement.startsWith('let ') && 
            !lastStatement.startsWith('const ') &&
            !lastStatement.startsWith('function ') &&
            !lastStatement.startsWith('if ') &&
            !lastStatement.startsWith('for ') &&
            !lastStatement.startsWith('while ') &&
            !lastStatement.startsWith('//') &&
            !lastStatement.endsWith('{') &&
            !lastStatement.endsWith('}')) {
          // 在最后一个语句前添加return
          statements[statements.length - 1] = 'return ' + lastStatement;
          processedCode = statements.join(';\n');
        }
      }
    }

    // 组合完整脚本
    // 注意：jsLib必须在nativeUtilFunctions之后加载，这样jsLib中的函数可以使用我们定义的source等对象
    // jsLib中的函数如getArguments需要在全局作用域可用
    // jsLib中的某些函数使用 const { source } = this; 解构this对象
    // 解决方案：使用.call()传递包含source等对象的上下文作为this
    const fullScript = `
      (function() {
        try {
          ${contextVars}
          ${variableVars}
          ${nativeUtilFunctions}
          
          // 创建this上下文对象，供jsLib中使用this的函数访问
          var __thisContext = {
            source: source,
            java: java,
            book: book,
            chapter: chapter,
            cookie: cookie,
            cache: cache,
            baseUrl: baseUrl,
            result: result
          };
          
          // 加载jsLib，让其中定义的函数在作用域内可用
          ${activeJsLib}
          
          // 如果jsLib中定义了setArguments函数，重新绑定其this上下文
          if (typeof setArguments === 'function') {
            var _originalSetArguments = setArguments;
            setArguments = function(key, value) {
              return _originalSetArguments.call(__thisContext, key, value);
            };
          }

          // 兼容处理：部分jsLib会覆盖java对象，补齐关键能力
          if (typeof java !== 'object' && typeof java !== 'function') {
            java = {};
          }
          if (typeof java.randomUUID !== 'function') {
            java.randomUUID = function() {
              return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
                var r = Math.random() * 16 | 0;
                var v = c === 'x' ? r : (r & 0x3 | 0x8);
                return v.toString(16);
              });
            };
          }
          if (!java.util || typeof java.util !== 'object') {
            java.util = {};
          }
          if (!java.util.UUID || typeof java.util.UUID !== 'object') {
            java.util.UUID = {};
          }
          if (typeof java.util.UUID.randomUUID !== 'function') {
            java.util.UUID.randomUUID = function() {
              var value = java.randomUUID();
              return {
                toString: function() { return value; }
              };
            };
          }
          __thisContext.java = java;
          
          var __originalResult__ = result;
          var __result__;
          var __evalCode__ = ${JSON.stringify(processedCode)};
          try {
            __result__ = eval(__evalCode__);
          } catch(__evalException__) {
            __result__ = (function() {
              ${processedCode}
            })();
          }

          var __finalResult__ = __result__;
          if (__finalResult__ && typeof __finalResult__ === 'object') {
            if (typeof __finalResult__.url !== 'undefined' && __finalResult__.url !== null) {
              __finalResult__ = __finalResult__.url;
            }
          }
          if (__finalResult__ === undefined || __finalResult__ === null || String(__finalResult__) === '') {
            if (typeof result !== 'undefined' && result !== null && result !== __originalResult__) {
              __finalResult__ = result;
            } else if (typeof url !== 'undefined' && url !== null && String(url) !== '') {
              __finalResult__ = url;
            } else if (typeof q !== 'undefined' && q !== null && String(q) !== '') {
              __finalResult__ = q;
            } else if (typeof u !== 'undefined' && u !== null && String(u) !== '') {
              __finalResult__ = u;
            } else if (typeof yp_url !== 'undefined' && yp_url !== null && String(yp_url) !== '') {
              __finalResult__ = yp_url;
            } else if (typeof audioUrl !== 'undefined' && audioUrl !== null && String(audioUrl) !== '') {
              __finalResult__ = audioUrl;
            } else if (typeof playUrl !== 'undefined' && playUrl !== null && String(playUrl) !== '') {
              __finalResult__ = playUrl;
            } else if (typeof requestUrl !== 'undefined' && requestUrl !== null && String(requestUrl) !== '') {
              __finalResult__ = requestUrl;
            } else if (typeof searchUrl !== 'undefined' && searchUrl !== null && String(searchUrl) !== '') {
              __finalResult__ = searchUrl;
            } else if (typeof __ctx_result !== 'undefined' && __ctx_result !== null && __ctx_result !== __originalResult__) {
              __finalResult__ = __ctx_result;
            }
          }

          if (__finalResult__ !== undefined && __finalResult__ !== null) {
            if (typeof __finalResult__ === 'object') {
              try {
                return JSON.stringify(__finalResult__);
              } catch(__jsonError__) {
                return String(__finalResult__);
              }
            }
            return String(__finalResult__);
          }
          return '';
        } catch(e) {
          return 'ERROR:' + e.message;
        }
      })();
    `;

    return fullScript;
  }

  /**
   * 简单表达式求值（不依赖WebView）
   * 用于处理简单的字符串操作和变量替换
   */
  private executeSimple(code: string, context: JsContext): JsExecuteResult {
    try {
      let processedCode = code;
      
      // 处理 cookie.removeCookie() 等副作用函数 - 直接忽略，返回空字符串
      if (processedCode.includes('cookie.removeCookie') || processedCode.includes('cookie.getCookie')) {
        // 提取cookie操作后面的实际代码
        const lines = processedCode.split(/[;\n]/).filter(line => line.trim() !== '');
        let foundUrl = false;
        for (let i = lines.length - 1; i >= 0; i--) {
          const line = lines[i].trim();
          if (line.includes('cookie.') || line.startsWith('//') || line.startsWith('var ') || line.startsWith('let ')) {
            continue;
          }
          if (line.startsWith('"') || line.startsWith("'") || line.startsWith('http') || line.includes('baseUrl')) {
            processedCode = line;
            foundUrl = true;
            break;
          }
        }
        if (!foundUrl) {
          // 整个代码都是cookie操作，返回空字符串
          return { success: true, result: '' };
        }
      }

      // 处理 source.getKey() - 返回书源URL（从context.variables中获取）
      if (processedCode.includes('source.getKey()')) {
        const sourceUrl = context.variables?.['sourceUrl'] || context.baseUrl || '';
        processedCode = processedCode.replace(/source\.getKey\(\)/g, `"${sourceUrl}"`);
      }

      // 处理简单的字符串拼接
      if (processedCode.includes('+') && !processedCode.includes('function')) {
        let result = processedCode;
        
        // 替换变量
        if (context.result !== undefined) {
          result = result.replace(/\bresult\b/g, `"${this.escapeString(context.result)}"`);
        }
        if (context.key !== undefined) {
          result = result.replace(/\bkey\b/g, `"${this.escapeString(context.key)}"`);
        }
        if (context.page !== undefined) {
          result = result.replace(/\bpage\b/g, String(context.page));
        }
        if (context.baseUrl !== undefined) {
          result = result.replace(/\bbaseUrl\b/g, `"${this.escapeString(context.baseUrl)}"`);
        }
        
        // 尝试简单求值
        try {
          const evalResult = this.simpleEval(result);
          return { success: true, result: evalResult };
        } catch (e) {
          // 求值失败，继续尝试其他方法
        }
      }

      // 处理简单的return语句
      const returnMatch = processedCode.match(/return\s+(.+?);?$/);
      if (returnMatch) {
        const expr = returnMatch[1].trim();
        
        // 替换变量
        let result = expr;
        if (context.result !== undefined) {
          result = result.replace(/\bresult\b/g, context.result);
        }
        
        // 如果是纯字符串
        if (result.startsWith('"') && result.endsWith('"')) {
          return { success: true, result: result.slice(1, -1) };
        }
        if (result.startsWith("'") && result.endsWith("'")) {
          return { success: true, result: result.slice(1, -1) };
        }
        
        return { success: true, result };
      }

      // 处理纯字符串
      if (/^["'][^"']*["']$/.test(processedCode.trim())) {
        return { success: true, result: processedCode.trim().slice(1, -1) };
      }

      // 处理简单数学表达式: page-1, page+1 等
      const mathMatch = processedCode.match(/^page\s*([+\-*/])\s*(\d+)$/);
      if (mathMatch && context.page !== undefined) {
        const operator = mathMatch[1];
        const operand = parseInt(mathMatch[2]);
        let result = context.page;
        switch (operator) {
          case '+': result = context.page + operand; break;
          case '-': result = context.page - operand; break;
          case '*': result = context.page * operand; break;
          case '/': result = Math.floor(context.page / operand); break;
        }
        return { success: true, result: String(result) };
      }

      // 无法处理的复杂代码
      logger.warn(TAG, `简单求值无法处理: ${code.substring(0, 100)}`);
      return { 
        success: false, 
        result: '', 
        error: 'JS执行需要WebView支持' 
      };
    } catch (error) {
      return {
        success: false,
        result: '',
        error: String(error)
      };
    }
  }

  /**
   * 简单表达式求值
   */
  private simpleEval(expr: string): string {
    // 只处理字符串拼接
    const parts = expr.split('+').map(p => p.trim());
    let result = '';
    
    for (const part of parts) {
      if (part.startsWith('"') && part.endsWith('"')) {
        result += part.slice(1, -1);
      } else if (part.startsWith("'") && part.endsWith("'")) {
        result += part.slice(1, -1);
      } else if (/^\d+$/.test(part)) {
        result += part;
      } else {
        // 无法处理的表达式
        throw new Error(`无法求值: ${part}`);
      }
    }
    
    return result;
  }

  /**
   * 转义字符串
   */
  private escapeString(str: string): string {
    return str
      .replace(/\\/g, '\\\\')
      .replace(/"/g, '\\"')
      .replace(/\n/g, '\\n')
      .replace(/\r/g, '\\r')
      .replace(/\t/g, '\\t');
  }

  /**
   * 检查是否就绪（WebView或Native引擎任一就绪即可）
   */
  isEngineReady(): boolean {
    return this.isReady || this.nativeEngineReady;
  }
  
  /**
   * 检查Native引擎是否就绪
   */
  isNativeEngineReady(): boolean {
    return this.nativeEngineReady;
  }

  /**
   * 重置引擎
   */
  reset(): void {
    this.webviewController = null;
    this.isReady = false;
    this.pendingTasks = [];
    this.jsLib = '';
    
    // 销毁Native引擎
    if (this.nativeEngine) {
      this.nativeEngine.destroy();
      this.nativeEngine = null;
      this.nativeEngineReady = false;
    }
    
    logger.info(TAG, 'JS引擎已重置');
  }
  
  /**
   * 设置是否使用Native引擎
   */
  setUseNativeEngine(use: boolean): void {
    this.useNativeEngine = use;
    if (use && !this.nativeEngineReady) {
      this.initNativeEngine();
    }
  }
}

/**
 * 获取JS引擎实例
 */
export function getLegadoJsEngine(): LegadoJsEngine {
  return LegadoJsEngine.getInstance();
}
