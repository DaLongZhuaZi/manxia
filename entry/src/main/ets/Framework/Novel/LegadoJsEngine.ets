/**
 * Legado JavaScript执行引擎
 * 优先使用Native JSVM引擎执行书源中的JavaScript代码
 * 当Native引擎不可用时，降级到WebView执行
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets
 */

import { webview } from '@kit.ArkWeb';
import { logger } from '../../Utils/Logger';
import { NativeJsEngine, JsContext as NativeJsContext, JsResult } from './NativeJsEngine';

const TAG = 'LegadoJsEngine';

/**
 * JS执行结果
 */
export interface JsExecuteResult {
  success: boolean;
  result: string;
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
    
    // 如果需要网络请求，优先使用WebView（WebView支持XMLHttpRequest同步请求）
    if (needsNetwork) {
      logger.debug(TAG, `JS代码包含网络请求函数，使用WebView执行`);
      
      if (this.isReady && this.webviewController) {
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
          // 检查是否返回错误
          if (result.result.startsWith('ERROR:')) {
            // Native执行返回错误，记录但仍然返回结果（可能是部分执行成功）
            const errorMsg = result.result.substring(6); // 移除"ERROR:"前缀
            logger.warn(TAG, `Native执行错误: ${errorMsg}`);
            // 返回空字符串作为结果，让调用方处理
            return { success: true, result: '' };
          }
          return { success: true, result: result.result };
        }
        // Native执行失败
        logger.warn(TAG, `Native执行失败: ${result.error}`);
        return { success: false, result: '', error: result.error || 'Native执行失败' };
      } catch (e) {
        logger.error(TAG, `Native执行异常: ${String(e)}`);
        return { success: false, result: '', error: String(e) };
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
    if (this.isReady && this.webviewController) {
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

    // 最后使用简单的表达式求值（仅当所有引擎都不可用时）
    logger.warn(TAG, 'Native和WebView都不可用，使用简单求值');
    return this.executeSimple(code, context);
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
   * 在WebView中执行JavaScript（带超时保护）
   */
  private async executeInWebView(code: string, context: JsContext): Promise<JsExecuteResult> {
    if (!this.webviewController) {
      return { success: false, result: '', error: 'WebView未初始化' };
    }

    try {
      // 构建执行脚本
      const script = this.buildScript(code, context);
      
      // 执行脚本（带超时保护，防止无限循环导致卡住）
      const TIMEOUT_MS = 30000; // 30秒超时
      const result = await this.runJavaScriptWithTimeout(script, TIMEOUT_MS);
      
      return {
        success: true,
        result: result ? String(result) : ''
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
        .then((result) => {
          if (!isResolved) {
            isResolved = true;
            clearTimeout(timeoutId);
            resolve(result ? String(result) : '');
          }
        })
        .catch((error: Error) => {
          if (!isResolved) {
            isResolved = true;
            clearTimeout(timeoutId);
            reject(error);
          }
        });
    });
  }

  /**
   * 构建执行脚本
   */
  private buildScript(code: string, context: JsContext): string {
    // 获取sourceUrl（优先从variables中获取，否则使用baseUrl）
    const sourceUrl = context.variables?.['sourceUrl'] || context.baseUrl || '';
    
    // 构建上下文变量
    const contextVars = `
      var result = ${JSON.stringify(context.result || '')};
      var baseUrl = ${JSON.stringify(context.baseUrl || '')};
      var sourceUrl = ${JSON.stringify(sourceUrl)};
      var key = ${JSON.stringify(context.key || '')};
      var page = ${context.page || 1};
      var book = ${JSON.stringify(context.book || {})};
      var chapter = ${JSON.stringify(context.chapter || {})};
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
        variableVars += `var ${varKey} = ${JSON.stringify(varValue)};\n`;
      }
    }

    // 添加常用工具函数（兼容Legado原版JsExtensions）
    const utilFunctions = `
      // source对象 - 模拟书源对象
      // sourceUrl是书源的bookSourceUrl，用于source.getKey()
      var source = {
        getKey: function() { return sourceUrl || baseUrl || ''; },
        bookSourceUrl: sourceUrl || baseUrl || '',
        bookSourceName: '',
        bookSourceGroup: '',
        bookSourceComment: '',
        loginUrl: '',
        loginUi: '',
        loginCheckJs: '',
        header: '',
        variableComment: ''
      };
      
      // cookie变量 - 用于存储和获取cookie（使用内存存储，避免document.cookie访问限制）
      var __cookieStore = {};
      var cookie = {
        getCookie: function(url) { 
          try { return __cookieStore[url] || document.cookie || ''; } 
          catch(e) { return __cookieStore[url] || ''; }
        },
        setCookie: function(url, value) { 
          __cookieStore[url] = value;
          try { document.cookie = value; } catch(e) { /* ignore */ }
        },
        removeCookie: function(url) { 
          delete __cookieStore[url];
          try { document.cookie = ''; } catch(e) { /* ignore */ }
        },
        cookieJar: __cookieStore
      };
      
      // 同步HTTP请求辅助函数（使用XMLHttpRequest同步模式）
      var __syncRequest = function(url, method, body, headers) {
        try {
          var xhr = new XMLHttpRequest();
          xhr.open(method || 'GET', url, false); // false = 同步
          xhr.timeout = 10000;
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
          return {
            body: xhr.responseText,
            url: xhr.responseURL || url,
            code: xhr.status,
            headers: xhr.getAllResponseHeaders()
          };
        } catch(e) {
          console.error('__syncRequest error:', e);
          return { body: '', url: url, code: 0, error: e.message };
        }
      };
      
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
        // get方法：如果参数是变量名（key/page/result/baseUrl），返回变量值；否则发起HTTP请求
        get: function(urlOrVarName, headers) {
          // 检查是否是变量获取
          if (urlOrVarName === 'key') return __ctx_key || '';
          if (urlOrVarName === 'page') return __ctx_page || 1;
          if (urlOrVarName === 'result') return __ctx_result || '';
          if (urlOrVarName === 'baseUrl') return __ctx_baseUrl || '';
          // 否则发起HTTP请求
          return __syncRequest(urlOrVarName, 'GET', null, headers);
        },
        // put方法：设置变量值
        put: function(varName, value) {
          if (varName === 'key') { __ctx_key = value; key = value; }
          if (varName === 'page') { __ctx_page = value; page = value; }
          if (varName === 'result') { __ctx_result = value; result = value; }
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
        
        // Base64编解码
        base64Decode: function(str, charset) { 
          try { return atob(str); } catch(e) { return str; }
        },
        base64Encode: function(str, flags) {
          try { return btoa(str); } catch(e) { return str; }
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
        
        // MD5编码（简化实现，真正的MD5需要异步调用md5EncodeAsync）
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
        md5Encode16: function(str) {
          return this.md5Encode(str).substring(8, 24);
        },
        // SHA编码（占位符，真正实现需要异步调用）
        sha256Encode: function(str) { return this.md5Encode(str); },
        sha1Encode: function(str) { return this.md5Encode(str).substring(0, 40); },
        
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
        
        // 弹窗提示（仅记录日志）
        toast: function(msg) { console.log('[Toast]', msg); },
        longToast: function(msg) { console.log('[LongToast]', msg); },
        
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
        
        // UUID生成
        randomUUID: function() {
          return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0;
            var v = c === 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
          });
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

    // 组合完整脚本
    const fullScript = `
      (function() {
        try {
          ${this.jsLib}
          ${contextVars}
          ${variableVars}
          ${utilFunctions}
          
          var __result__ = (function() {
            ${code}
          })();
          
          return __result__ !== undefined ? String(__result__) : '';
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
    
    // 构建上下文变量
    const contextVars = `
      var result = ${JSON.stringify(context.result || '')};
      var baseUrl = ${JSON.stringify(context.baseUrl || '')};
      var sourceUrl = ${JSON.stringify(sourceUrl)};
      var key = ${JSON.stringify(context.key || '')};
      var page = ${context.page || 1};
      var book = ${JSON.stringify(context.book || {})};
      var chapter = ${JSON.stringify(context.chapter || {})};
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
        variableVars += `var ${varKey} = ${JSON.stringify(varValue)};\n`;
      }
    }

    // 简化的辅助函数（适用于Native JSVM）
    const nativeUtilFunctions = `
      // source对象 - 模拟书源对象
      // sourceUrl是书源的bookSourceUrl，用于source.getKey()
      var source = {
        getKey: function() { return sourceUrl || baseUrl || ''; },
        bookSourceUrl: sourceUrl || baseUrl || '',
        bookSourceName: '',
        bookSourceGroup: '',
        bookSourceComment: '',
        loginUrl: '',
        loginUi: '',
        loginCheckJs: '',
        header: '',
        variableComment: ''
      };
      
      // cookie变量 - 用于存储和获取cookie（Native环境简化实现）
      var cookie = {
        getCookie: function(url) { return ''; },
        setCookie: function(url, value) { },
        removeCookie: function(url) { },
        cookieJar: {}
      };
      
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
          return ''; 
        },
        put: function(varName, value) { 
          if (varName === 'key') { __ctx_key = value; key = value; }
          if (varName === 'page') { __ctx_page = value; page = value; }
          if (varName === 'result') { __ctx_result = value; result = value; }
          return value;
        },
        
        // Base64编解码
        base64Decode: function(str, charset) { 
          try { return decodeURIComponent(escape(atob(str))); } catch(e) { return str; }
        },
        base64Encode: function(str, flags) {
          try { return btoa(unescape(encodeURIComponent(str))); } catch(e) { return str; }
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
        
        // UUID生成
        randomUUID: function() {
          return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0;
            var v = c === 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
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
        
        // Ajax请求（在Native环境中返回空）
        ajax: function(url) { return ''; },
        ajaxAll: function(urls) { return []; },
        
        // 获取字符串
        getString: function(rule, isUrl) { return ''; },
        getStringList: function(rule, isUrl) { return []; },
        getElements: function(rule) { return []; },
        
        // Cookie操作
        getCookie: function(url, key) { return ''; },
        setCookie: function(url, cookie) { },
        removeCookie: function(url) { },
        
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
      
      // cookie对象 - 兼容书源中的cookie操作
      var cookie = {
        getCookie: function(url, key) { return ''; },
        setCookie: function(url, cookie) { },
        removeCookie: function(url) { }
      };
    `;

    // 组合完整脚本
    const fullScript = `
      (function() {
        try {
          ${contextVars}
          ${variableVars}
          ${nativeUtilFunctions}
          ${this.jsLib}
          
          var __result__ = (function() {
            ${code}
          })();
          
          return __result__ !== undefined ? String(__result__) : '';
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
