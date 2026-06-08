import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * Rhino WASM执行器
 * 
 * 通过WebView加载CheerpJ + Rhino WASM沙箱，实现与Android Legado完全兼容的JS执行环境
 * 
 * 核心特点：
 * 1. 使用CheerpJ将Rhino引擎编译为WASM运行在WebView中
 * 2. 完整支持Legado的java.xxx扩展函数
 * 3. 支持Jsoup DOM解析
 * 4. 与Android端代码1:1对齐
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/RhinoWasmExecutor.ets
 */

import { webview } from '@kit.ArkWeb';
import { logger } from '../../Utils/Logger';

const TAG = 'RhinoWasmExecutor';

/**
 * 执行结果接口
 */
export interface RhinoExecuteResult {
  success: boolean;
  result: string;
  error?: string;
  taskId?: string;
  pending?: boolean;
}

/**
 * 执行上下文接口
 */
export interface RhinoContext {
  /** 上一步的结果/页面内容 */
  result?: string;
  /** 基础URL */
  baseUrl?: string;
  /** 书源URL */
  sourceUrl?: string;
  /** 搜索关键字 */
  key?: string;
  /** 页码 */
  page?: number;
  /** 书籍信息 */
  book?: Record<string, string>;
  /** 章节信息 */
  chapter?: Record<string, string>;
  /** 自定义变量 */
  variables?: Record<string, string>;
  /** 书源变量 */
  sourceVariable?: string;
  /** 登录信息 */
  loginInfo?: string;
  /** 登录头信息 */
  loginHeader?: string;
}

/**
 * 待执行任务
 */
interface PendingTask {
  taskId: string;
  script: string;
  context: RhinoContext;
  resolve: (result: RhinoExecuteResult) => void;
  reject: (error: Error) => void;
  timeoutId?: number;
}

/**
 * 沙箱状态
 */
interface SandboxStatus {
  ready: boolean;
  cheerpjReady: boolean;
  rhinoReady: boolean;
  error: string | null;
  pendingCount: number;
}

/**
 * Rhino WASM执行器
 * 单例模式，管理WebView沙箱实例
 */
export class RhinoWasmExecutor {
  private static instance: RhinoWasmExecutor | null = null;
  
  private webviewController: webview.WebviewController | null = null;
  private isInitialized: boolean = false;
  private sandboxReady: boolean = false;
  private initError: string | null = null;
  
  private pendingTasks: Map<string, PendingTask> = new Map();
  private taskIdCounter: number = 0;
  
  private statusCheckInterval: number | null = null;
  private initPromise: Promise<boolean> | null = null;
  
  private constructor() {}
  
  /**
   * 获取单例实例
   */
  static getInstance(): RhinoWasmExecutor {
    if (!RhinoWasmExecutor.instance) {
      RhinoWasmExecutor.instance = new RhinoWasmExecutor();
    }
    return RhinoWasmExecutor.instance;
  }
  
  /**
   * 设置WebView控制器
   * 由UI层调用，传入已创建的WebView控制器
   */
  setWebviewController(controller: webview.WebviewController): void {
    this.webviewController = controller;
    logger.info(TAG, 'WebView控制器已设置');
  }
  
  /**
   * 初始化沙箱
   * 加载本地HTML并等待CheerpJ + Rhino初始化完成
   */
  async initialize(): Promise<boolean> {
    if (this.sandboxReady) {
      return true;
    }
    
    if (this.initPromise) {
      return this.initPromise;
    }
    
    this.initPromise = this.doInitialize();
    return this.initPromise;
  }
  
  private async doInitialize(): Promise<boolean> {
    if (!this.webviewController) {
      this.initError = 'WebView控制器未设置';
      logger.error(TAG, this.initError);
      return false;
    }
    
    try {
      logger.info(TAG, '开始初始化Rhino WASM沙箱...');
      
      // 先等待WebView准备好（about:blank页面加载完成）
      // WebView刚创建时可能还没准备好执行JavaScript
      logger.debug(TAG, '等待WebView准备就绪...');
      await this.sleep(500); // 给WebView一些时间初始化
      
      // 直接通过runJavaScript注入沙箱代码
      const sandboxScript = this.getSandboxScript();
      logger.debug(TAG, `注入沙箱脚本，长度: ${sandboxScript.length}`);
      
      // 使用Promise.race添加超时保护，避免runJavaScript无限等待
      const injectPromise = this.webviewController.runJavaScript(sandboxScript);
      const timeoutPromise = new Promise<string>((_, reject) => {
        setTimeout(() => reject(new Error('runJavaScript超时')), 3000);
      });
      
      try {
        await Promise.race([injectPromise, timeoutPromise]);
        logger.info(TAG, '沙箱脚本注入成功');
      } catch (e) {
        logger.error(TAG, `沙箱脚本注入失败: ${String(e)}`);
        return false;
      }
      
      this.isInitialized = true;
      
      // 等待沙箱就绪（应该立即就绪）
      const ready = await this.waitForSandboxReady(3000); // 3秒超时
      
      if (ready) {
        this.sandboxReady = true;
        logger.info(TAG, 'Rhino WASM沙箱初始化成功');
        
        // 启动状态检查
        this.startStatusCheck();
        
        return true;
      } else {
        this.initError = '沙箱初始化超时';
        logger.error(TAG, this.initError);
        return false;
      }
      
    } catch (error) {
      this.initError = String(error);
      logger.error(TAG, `沙箱初始化失败: ${this.initError}`);
      return false;
    }
  }
  
  /**
   * 获取沙箱脚本（纯JS，用于runJavaScript注入）
   * 完整实现Legado书源所需的所有API
   */
  private getSandboxScript(): string {
    return `
// ========== Rhino沙箱初始化脚本 ==========
// 完整实现Legado书源所需的所有API
(function() {
  // 如果已经初始化，直接返回
  if (window.rhinoSandbox && window.rhinoSandbox.ready) {
    return;
  }
  
  // ========== 沙箱状态 ==========
  window.rhinoSandbox = {
    ready: false,
    mode: 'offline',
    error: null,
    pendingTasks: [],
    results: {}
  };

  // ========== 全局变量初始化 ==========
  window.result = '';
  window.baseUrl = '';
  window.key = '';
  window.page = 1;
  window.sourceUrl = '';
  window._arguments = {};
  window._loginInfo = '';
  window._loginHeader = '';
  window._sourceVariable = '';
  window._vars = {};
  window._cookies = {};
  window._cache = {};

  // ========== Jsoup实现（使用DOMParser） ==========
  window.JsoupDocument = function(html) {
    this._html = html || '';
    this._doc = null;
    try {
      var parser = new DOMParser();
      this._doc = parser.parseFromString(this._html, 'text/html');
    } catch (e) {
      console.log('[Jsoup] DOMParser error:', e);
    }
  };
  
  JsoupDocument.prototype.title = function() {
    if (this._doc) {
      var el = this._doc.querySelector('title');
      return el ? el.textContent : '';
    }
    var m = this._html.match(/<title[^>]*>([^<]*)<\\/title>/i);
    return m ? m[1] : '';
  };
  
  JsoupDocument.prototype.select = function(selector) {
    if (!this._doc) return new JsoupElements([]);
    try {
      var els = this._doc.querySelectorAll(selector);
      var arr = [];
      for (var i = 0; i < els.length; i++) {
        arr.push(new JsoupElement(els[i], this));
      }
      return new JsoupElements(arr);
    } catch (e) {
      console.log('[Jsoup] select error:', e);
      return new JsoupElements([]);
    }
  };
  
  JsoupDocument.prototype.selectFirst = function(selector) {
    var els = this.select(selector);
    return els.size() > 0 ? els.get(0) : null;
  };
  
  JsoupDocument.prototype.body = function() {
    if (this._doc && this._doc.body) {
      return new JsoupElement(this._doc.body, this);
    }
    return new JsoupElement(null, this);
  };
  
  JsoupDocument.prototype.head = function() {
    if (this._doc && this._doc.head) {
      return new JsoupElement(this._doc.head, this);
    }
    return new JsoupElement(null, this);
  };
  
  JsoupDocument.prototype.text = function() {
    if (this._doc && this._doc.body) {
      return this._doc.body.textContent || '';
    }
    return this._html.replace(/<[^>]+>/g, '');
  };
  
  JsoupDocument.prototype.html = function() { return this._html; };
  JsoupDocument.prototype.outerHtml = function() { return this._html; };
  
  JsoupDocument.prototype.getElementById = function(id) {
    if (!this._doc) return null;
    var el = this._doc.getElementById(id);
    return el ? new JsoupElement(el, this) : null;
  };
  
  JsoupDocument.prototype.getElementsByTag = function(tag) {
    if (!this._doc) return new JsoupElements([]);
    var els = this._doc.getElementsByTagName(tag);
    var arr = [];
    for (var i = 0; i < els.length; i++) {
      arr.push(new JsoupElement(els[i], this));
    }
    return new JsoupElements(arr);
  };
  
  JsoupDocument.prototype.getElementsByClass = function(className) {
    if (!this._doc) return new JsoupElements([]);
    var els = this._doc.getElementsByClassName(className);
    var arr = [];
    for (var i = 0; i < els.length; i++) {
      arr.push(new JsoupElement(els[i], this));
    }
    return new JsoupElements(arr);
  };

  window.JsoupElement = function(el, doc) {
    this._el = el;
    this._doc = doc;
  };
  
  JsoupElement.prototype.text = function() { 
    return this._el ? (this._el.textContent || '') : ''; 
  };
  
  JsoupElement.prototype.ownText = function() {
    if (!this._el) return '';
    var text = '';
    for (var i = 0; i < this._el.childNodes.length; i++) {
      var node = this._el.childNodes[i];
      if (node.nodeType === 3) { // TEXT_NODE
        text += node.textContent;
      }
    }
    return text.trim();
  };
  
  JsoupElement.prototype.html = function() { 
    return this._el ? (this._el.innerHTML || '') : ''; 
  };
  
  JsoupElement.prototype.outerHtml = function() { 
    return this._el ? (this._el.outerHTML || '') : ''; 
  };
  
  JsoupElement.prototype.attr = function(name) {
    if (!this._el) return '';
    // 特殊属性处理
    if (name === 'href' || name === 'src') {
      return this._el.getAttribute(name) || '';
    }
    if (name === 'text') {
      return this.text();
    }
    if (name === 'html') {
      return this.html();
    }
    if (name === 'outerHtml') {
      return this.outerHtml();
    }
    return this._el.getAttribute(name) || '';
  };
  
  JsoupElement.prototype.hasAttr = function(name) {
    return this._el ? this._el.hasAttribute(name) : false;
  };
  
  JsoupElement.prototype.select = function(selector) {
    if (!this._el) return new JsoupElements([]);
    try {
      var els = this._el.querySelectorAll(selector);
      var arr = [];
      for (var i = 0; i < els.length; i++) {
        arr.push(new JsoupElement(els[i], this._doc));
      }
      return new JsoupElements(arr);
    } catch (e) {
      return new JsoupElements([]);
    }
  };
  
  JsoupElement.prototype.selectFirst = function(selector) {
    var els = this.select(selector);
    return els.size() > 0 ? els.get(0) : null;
  };
  
  JsoupElement.prototype.tagName = function() { 
    return this._el ? this._el.tagName.toLowerCase() : ''; 
  };
  
  JsoupElement.prototype.id = function() { 
    return this._el ? (this._el.id || '') : ''; 
  };
  
  JsoupElement.prototype.className = function() { 
    return this._el ? (this._el.className || '') : ''; 
  };
  
  JsoupElement.prototype.parent = function() {
    if (!this._el || !this._el.parentElement) return null;
    return new JsoupElement(this._el.parentElement, this._doc);
  };
  
  JsoupElement.prototype.children = function() {
    if (!this._el) return new JsoupElements([]);
    var arr = [];
    for (var i = 0; i < this._el.children.length; i++) {
      arr.push(new JsoupElement(this._el.children[i], this._doc));
    }
    return new JsoupElements(arr);
  };
  
  JsoupElement.prototype.child = function(index) {
    if (!this._el || index < 0 || index >= this._el.children.length) return null;
    return new JsoupElement(this._el.children[index], this._doc);
  };
  
  JsoupElement.prototype.previousElementSibling = function() {
    if (!this._el || !this._el.previousElementSibling) return null;
    return new JsoupElement(this._el.previousElementSibling, this._doc);
  };
  
  JsoupElement.prototype.nextElementSibling = function() {
    if (!this._el || !this._el.nextElementSibling) return null;
    return new JsoupElement(this._el.nextElementSibling, this._doc);
  };
  
  JsoupElement.prototype.getElementsByTag = function(tag) {
    if (!this._el) return new JsoupElements([]);
    var els = this._el.getElementsByTagName(tag);
    var arr = [];
    for (var i = 0; i < els.length; i++) {
      arr.push(new JsoupElement(els[i], this._doc));
    }
    return new JsoupElements(arr);
  };
  
  JsoupElement.prototype.getElementsByClass = function(className) {
    if (!this._el) return new JsoupElements([]);
    var els = this._el.getElementsByClassName(className);
    var arr = [];
    for (var i = 0; i < els.length; i++) {
      arr.push(new JsoupElement(els[i], this._doc));
    }
    return new JsoupElements(arr);
  };

  window.JsoupElements = function(els) { 
    this._els = els || []; 
  };
  
  JsoupElements.prototype.size = function() { 
    return this._els.length; 
  };
  
  JsoupElements.prototype.isEmpty = function() {
    return this._els.length === 0;
  };
  
  JsoupElements.prototype.get = function(i) { 
    return i >= 0 && i < this._els.length ? this._els[i] : null; 
  };
  
  JsoupElements.prototype.first = function() { 
    return this.get(0); 
  };
  
  JsoupElements.prototype.last = function() { 
    return this.get(this._els.length - 1); 
  };
  
  JsoupElements.prototype.eq = function(index) {
    return this.get(index);
  };
  
  JsoupElements.prototype.text = function() { 
    var result = [];
    for (var i = 0; i < this._els.length; i++) {
      result.push(this._els[i].text());
    }
    return result.join(' '); 
  };
  
  JsoupElements.prototype.html = function() {
    if (this._els.length > 0) {
      return this._els[0].html();
    }
    return '';
  };
  
  JsoupElements.prototype.outerHtml = function() {
    if (this._els.length > 0) {
      return this._els[0].outerHtml();
    }
    return '';
  };
  
  JsoupElements.prototype.attr = function(name) {
    if (this._els.length > 0) {
      return this._els[0].attr(name);
    }
    return '';
  };
  
  JsoupElements.prototype.eachText = function() {
    var result = [];
    for (var i = 0; i < this._els.length; i++) {
      result.push(this._els[i].text());
    }
    return result;
  };
  
  JsoupElements.prototype.eachAttr = function(name) {
    var result = [];
    for (var i = 0; i < this._els.length; i++) {
      result.push(this._els[i].attr(name));
    }
    return result;
  };
  
  JsoupElements.prototype.select = function(selector) {
    var result = [];
    for (var i = 0; i < this._els.length; i++) {
      var els = this._els[i].select(selector);
      for (var j = 0; j < els.size(); j++) {
        result.push(els.get(j));
      }
    }
    return new JsoupElements(result);
  };

  window.Jsoup = {
    parse: function(html) { return new JsoupDocument(html); },
    connect: function(url) {
      // 返回一个模拟的Connection对象
      return {
        _url: url,
        _method: 'GET',
        _headers: {},
        _data: {},
        method: function(m) { this._method = m; return this; },
        header: function(k, v) { this._headers[k] = v; return this; },
        data: function(k, v) { this._data[k] = v; return this; },
        get: function() { return new JsoupDocument(''); },
        post: function() { return new JsoupDocument(''); },
        execute: function() { return { body: '' }; }
      };
    }
  };

  // ========== java对象（完整实现） ==========
  window.java = {
    // 变量存储
    _vars: {},
    
    // 网络请求（在WebView沙箱中无法真正发起，返回空）
    ajax: function(url) { 
      console.log('[java.ajax] URL:', url);
      return ''; 
    },
    ajaxAll: function(urls) { 
      console.log('[java.ajaxAll] URLs:', urls);
      return []; 
    },
    connect: function(url) { 
      console.log('[java.connect] URL:', url);
      return { body: '', code: 200 }; 
    },
    post: function(url, body, headers) { 
      console.log('[java.post] URL:', url);
      return ''; 
    },
    get: function(key) {
      // 如果是URL则发起请求，否则获取变量
      if (typeof key === 'string' && key.startsWith('http')) {
        console.log('[java.get] URL:', key);
        return '';
      }
      // 优先从全局变量获取
      if (key === 'result') return window.result || '';
      if (key === 'baseUrl') return window.baseUrl || '';
      if (key === 'key') return window.key || '';
      if (key === 'page') return window.page || 1;
      if (key === 'sourceUrl') return window.sourceUrl || '';
      return this._vars[key] || window['_var_' + key] || '';
    },
    
    // 变量操作
    put: function(key, value) { 
      this._vars[key] = value;
      window['_var_' + key] = value;
      // 同步更新全局变量
      if (key === 'result') window.result = value;
      if (key === 'baseUrl') window.baseUrl = value;
      if (key === 'key') window.key = value;
      if (key === 'page') window.page = value;
    },
    getString: function(key) { 
      return String(this.get(key) || '');
    },
    getInt: function(key) {
      return parseInt(this.get(key)) || 0;
    },
    
    // Toast消息（在沙箱中只能打印日志）
    toast: function(msg) {
      console.log('[java.toast]', msg);
    },
    longToast: function(msg) {
      console.log('[java.longToast]', msg);
    },
    
    // 设备信息
    deviceID: function() {
      // 生成一个模拟的设备ID
      if (!window._deviceId) {
        window._deviceId = this.uuid().replace(/-/g, '');
      }
      return window._deviceId;
    },
    androidId: function() {
      return this.deviceID().substring(0, 16);
    },
    getWebViewUA: function() {
      return navigator.userAgent || 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36';
    },
    
    // Cookie操作
    getCookie: function(url) {
      return window.cookie.getCookie(url);
    },
    
    // 十六进制编解码
    hexDecodeToString: function(hex) {
      if (!hex) return '';
      try {
        var str = '';
        for (var i = 0; i < hex.length; i += 2) {
          str += String.fromCharCode(parseInt(hex.substr(i, 2), 16));
        }
        return decodeURIComponent(escape(str));
      } catch(e) {
        try {
          var str = '';
          for (var i = 0; i < hex.length; i += 2) {
            str += String.fromCharCode(parseInt(hex.substr(i, 2), 16));
          }
          return str;
        } catch(e2) {
          return hex;
        }
      }
    },
    hexEncodeToString: function(str) {
      if (!str) return '';
      var hex = '';
      for (var i = 0; i < str.length; i++) {
        hex += str.charCodeAt(i).toString(16).padStart(2, '0');
      }
      return hex;
    },
    
    // Base64编解码
    base64Decode: function(str) {
      if (!str) return '';
      try { 
        return decodeURIComponent(escape(atob(str))); 
      } catch(e) { 
        try { return atob(str); } catch(e2) { return str; }
      }
    },
    base64DecodeToByteArray: function(str) {
      return this.base64Decode(str);
    },
    base64Encode: function(str) {
      if (!str) return '';
      try { 
        return btoa(unescape(encodeURIComponent(str))); 
      } catch(e) { 
        try { return btoa(str); } catch(e2) { return str; }
      }
    },
    
    // 时间格式化
    timeFormat: function(ts, fmt) {
      var d = new Date(typeof ts === 'number' ? ts : parseInt(ts) || Date.now());
      if (!fmt) fmt = 'yyyy-MM-dd HH:mm:ss';
      var o = {
        'M+': d.getMonth() + 1,
        'd+': d.getDate(),
        'H+': d.getHours(),
        'h+': d.getHours() % 12 || 12,
        'm+': d.getMinutes(),
        's+': d.getSeconds(),
        'q+': Math.floor((d.getMonth() + 3) / 3),
        'S': d.getMilliseconds()
      };
      if (/(y+)/.test(fmt)) {
        fmt = fmt.replace(RegExp.$1, (d.getFullYear() + '').substr(4 - RegExp.$1.length));
      }
      for (var k in o) {
        if (new RegExp('(' + k + ')').test(fmt)) {
          fmt = fmt.replace(RegExp.$1, RegExp.$1.length === 1 ? o[k] : ('00' + o[k]).substr(('' + o[k]).length));
        }
      }
      return fmt;
    },
    
    // 日志
    log: function(msg) { 
      console.log('[java.log]', msg); 
    },
    logType: function(obj) { 
      console.log('[java.logType]', typeof obj, obj); 
    },
    
    // 字符串处理
    strToInt: function(str, def) {
      var n = parseInt(str);
      return isNaN(n) ? (def || 0) : n;
    },
    strToLong: function(str, def) {
      return this.strToInt(str, def);
    },
    
    // MD5（简化实现）
    md5Encode: function(str) {
      var hash = 0;
      for (var i = 0; i < str.length; i++) {
        var char = str.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash;
      }
      return Math.abs(hash).toString(16).padStart(32, '0');
    },
    md5Encode16: function(str) {
      return this.md5Encode(str).substring(8, 24);
    },
    
    // URL编解码
    urlEncode: function(str) {
      return encodeURIComponent(str || '');
    },
    urlDecode: function(str) {
      return decodeURIComponent(str || '');
    },
    
    // HTML实体编解码
    htmlDecode: function(str) {
      if (!str) return '';
      var div = document.createElement('div');
      div.innerHTML = str;
      return div.textContent || div.innerText || '';
    },
    
    // 正则
    regexMatch: function(str, regex, group) {
      if (!str || !regex) return '';
      try {
        var m = str.match(new RegExp(regex));
        if (m) {
          return group !== undefined && m[group] !== undefined ? m[group] : m[0];
        }
      } catch(e) {}
      return '';
    },
    
    // 随机数
    random: function(min, max) {
      if (max === undefined) {
        max = min;
        min = 0;
      }
      return Math.floor(Math.random() * (max - min + 1)) + min;
    },
    
    // UUID
    uuid: function() {
      return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        var r = Math.random() * 16 | 0;
        var v = c === 'x' ? r : (r & 0x3 | 0x8);
        return v.toString(16);
      });
    },
    
    // 浏览器相关（在沙箱中无法实现，返回模拟值）
    startBrowserAwait: function(url, title) {
      console.log('[java.startBrowserAwait] URL:', url, 'Title:', title);
      return { body: function() { return ''; } };
    },
    startBrowser: function(url, title) {
      console.log('[java.startBrowser] URL:', url, 'Title:', title);
    },
    
    // 文件操作（在沙箱中无法实现）
    cacheFile: '',
    downloadFile: function(url) {
      console.log('[java.downloadFile] URL:', url);
      return '';
    },
    
    // 加解密
    aesDecodeToString: function(data, key, transformation, iv) {
      console.log('[java.aesDecodeToString] Not implemented');
      return data;
    },
    aesEncodeToString: function(data, key, transformation, iv) {
      console.log('[java.aesEncodeToString] Not implemented');
      return data;
    }
  };

  // ========== source对象（完整实现） ==========
  window.source = {
    bookSourceUrl: '',
    bookSourceName: '',
    bookSourceGroup: '',
    bookSourceType: 0,
    loginUrl: '',
    loginUi: '',
    loginCheckJs: '',
    header: '',
    
    getKey: function() {
      return this.bookSourceUrl || window.sourceUrl || '';
    },
    
    getLoginInfo: function() { 
      return window._loginInfo || ''; 
    },
    getLoginInfoMap: function() {
      try {
        return SafeUtils.parseObj(window._loginInfo || '{}');
      } catch(e) {
        return {};
      }
    },
    getLoginHeader: function() { 
      return window._loginHeader || ''; 
    },
    getLoginHeaderMap: function() {
      try {
        return SafeUtils.parseObj(window._loginHeader || '{}');
      } catch(e) {
        return {};
      }
    },
    putLoginInfo: function(info) { 
      if (typeof info === 'object') {
        window._loginInfo = JSON.stringify(info);
      } else {
        window._loginInfo = info || '';
      }
    },
    putLoginHeader: function(header) { 
      if (typeof header === 'object') {
        window._loginHeader = JSON.stringify(header);
      } else {
        window._loginHeader = header || '';
      }
    },
    
    getVariable: function() { 
      return window._sourceVariable || ''; 
    },
    setVariable: function(v) { 
      window._sourceVariable = v || ''; 
    },
    
    // 获取书源配置
    getBookSourceConfig: function() {
      return {
        bookSourceUrl: this.bookSourceUrl,
        bookSourceName: this.bookSourceName,
        bookSourceGroup: this.bookSourceGroup,
        bookSourceType: this.bookSourceType
      };
    }
  };

  // ========== cookie对象（完整实现） ==========
  window.cookie = {
    _cookies: {},
    
    getCookie: function(url) { 
      return this._cookies[url] || ''; 
    },
    setCookie: function(url, cookieStr) {
      this._cookies[url] = cookieStr || '';
    },
    replaceCookie: function(url, cookieStr) {
      this.setCookie(url, cookieStr);
    },
    removeCookie: function(url) {
      delete this._cookies[url];
    },
    clearCookie: function() {
      this._cookies = {};
    },
    
    // 合并Cookie
    mergeCookie: function(url, cookieStr) {
      var existing = this._cookies[url] || '';
      if (existing && cookieStr) {
        this._cookies[url] = existing + '; ' + cookieStr;
      } else {
        this._cookies[url] = cookieStr || existing;
      }
    },
    
    // 从Cookie中获取指定key的值
    getKey: function(cookieStr, key) {
      if (!cookieStr) return '';
      if (!key) {
        // 如果没有指定key，返回整个cookie字符串
        return cookieStr;
      }
      var regex = new RegExp(key + '=([^;]*)');
      var match = cookieStr.match(regex);
      return match ? match[1] : '';
    }
  };

  // ========== cache对象（完整实现） ==========
  window.cache = {
    _data: {},
    
    get: function(key) { 
      var item = this._data[key];
      if (item) {
        if (item.expireTime && Date.now() > item.expireTime) {
          delete this._data[key];
          return '';
        }
        return item.value || '';
      }
      return ''; 
    },
    put: function(key, value, saveTime) { 
      var expireTime = null;
      if (saveTime && saveTime > 0) {
        expireTime = Date.now() + saveTime * 1000;
      }
      this._data[key] = { value: value, expireTime: expireTime };
    },
    delete: function(key) { 
      delete this._data[key]; 
    },
    deleteDatabase: function() {
      this._data = {};
    },
    
    // 获取所有key
    getKeys: function() {
      return Object.keys(this._data);
    }
  };

  // ========== 全局辅助函数（完整实现） ==========
  // getArguments - 获取传入的参数（通常是表单数据）
  // 注意：书源中的getArguments有两种用法：
  // 1. getArguments() - 返回所有参数
  // 2. getArguments(jsonStr, key) - 从JSON字符串中获取指定key的值
  window.getArguments = function(jsonStr, key) {
    if (arguments.length === 0) {
      return window._arguments || {};
    }
    // 书源中的用法：getArguments(open_argument, 'server')
    try {
      var obj = typeof jsonStr === 'string' ? SafeUtils.parseObj(jsonStr) : jsonStr;
      if (key === '' || key === undefined) {
        return obj;
      }
      return obj[key] || '';
    } catch(e) {
      return key ? '' : {};
    }
  };
  
  // getArgument - 单数形式，从source.getVariable()中获取参数
  window.getArgument = function(key) {
    try {
      var varStr = window.source.getVariable() || '{}';
      var obj = SafeUtils.parseObj(varStr);
      return obj[key] || '';
    } catch(e) {
      return '';
    }
  };
  
  // setArgument - 设置参数到source.setVariable()
  window.setArgument = function(key, value) {
    try {
      var varStr = window.source.getVariable() || '{}';
      var obj = SafeUtils.parseObj(varStr);
      obj[key] = value;
      window.source.setVariable(JSON.stringify(obj));
      return JSON.stringify(obj);
    } catch(e) {
      var obj = {};
      obj[key] = value;
      window.source.setVariable(JSON.stringify(obj));
      return JSON.stringify(obj);
    }
  };
  
  // putLoginInfo - 保存登录信息
  window.putLoginInfo = function(info) {
    window.source.putLoginInfo(info);
  };
  
  // getKey - 从cookie字符串中提取key值（书源中常用）
  // 注意：这个函数在书源中用于从cookie中提取qttoken等
  window.getKey = function(cookieStr) {
    if (!cookieStr) return '';
    // 尝试提取qttoken
    var match = cookieStr.match(/qttoken=([^;]*)/);
    if (match) return match[1];
    // 尝试提取key
    match = cookieStr.match(/key=([^;]*)/);
    if (match) return match[1];
    // 尝试提取token
    match = cookieStr.match(/token=([^;]*)/);
    if (match) return match[1];
    return '';
  };
  
  // removeCookie - 全局函数，删除指定URL的cookie
  window.removeCookie = function(url) {
    window.cookie.removeCookie(url);
  };
  
  // getFanqieCookie - 获取番茄小说的cookie
  window.getFanqieCookie = function() {
    // 尝试从多个可能的URL获取番茄cookie
    var urls = [
      'https://fanqienovel.com',
      'https://www.fanqienovel.com',
      'fanqie'
    ];
    for (var i = 0; i < urls.length; i++) {
      var ck = window.cookie.getCookie(urls[i]);
      if (ck) return ck;
    }
    return '';
  };
  
  // getSessionId - 从cookie中提取sessionid
  window.getSessionId = function(cookieStr) {
    if (!cookieStr) return '';
    var match = cookieStr.match(/sessionid=([^;]*)/);
    return match ? match[1] : '';
  };
  
  // 获取result变量
  window.getResult = function() {
    return window.result || '';
  };
  
  // 获取baseUrl变量
  window.getBaseUrl = function() {
    return window.baseUrl || '';
  };
  
  // 获取page变量
  window.getPage = function() {
    return window.page || 1;
  };
  
  // 获取sourceUrl变量
  window.getSourceUrl = function() {
    return window.sourceUrl || '';
  };
  
  // book对象（书籍信息）
  window.book = {
    name: '',
    author: '',
    bookUrl: '',
    coverUrl: '',
    intro: '',
    kind: '',
    lastChapter: '',
    tocUrl: '',
    durChapterIndex: 0,
    readConfig: null,
    getVariable: function(key) {
      if (!this._vars) this._vars = {};
      return this._vars[key] || '';
    },
    setVariable: function(key, value) {
      if (!this._vars) this._vars = {};
      this._vars[key] = value;
    },
    setUseReplaceRule: function(use) {
      if (!this.readConfig) this.readConfig = {};
      this.readConfig.useReplaceRule = use;
    },
    _vars: {}
  };
  
  // chapter对象（章节信息）
  window.chapter = {
    title: '',
    url: '',
    index: 0,
    bookUrl: '',
    isVip: false,
    isPay: false
  };

  // ========== 字符串扩展方法 ==========
  if (!String.prototype.toJSON) {
    String.prototype.toJSON = function() {
      try {
        return SafeUtils.parseObj(this);
      } catch(e) {
        return {};
      }
    };
  }
  
  if (!String.prototype.parseJSON) {
    String.prototype.parseJSON = function() {
      return this.toJSON();
    };
  }

  // ========== 执行脚本 ==========
  window.executeScript = function(taskId, script, contextJson) {
    try {
      var ctx = contextJson ? SafeUtils.parseObj(contextJson) : {};
      
      // 设置全局变量
      window.result = ctx.result || '';
      window.baseUrl = ctx.baseUrl || '';
      window.key = ctx.key || '';
      window.page = ctx.page || 1;
      window.sourceUrl = ctx.sourceUrl || ctx.baseUrl || '';
      
      // 设置source对象属性
      if (ctx.sourceUrl) {
        window.source.bookSourceUrl = ctx.sourceUrl;
      }
      
      // 设置arguments（表单数据等）
      if (ctx.result) {
        try {
          window._arguments = SafeUtils.parseObj(ctx.result);
        } catch(e) {
          window._arguments = {};
        }
      } else {
        window._arguments = {};
      }
      
      // 设置variables中的变量
      if (ctx.variables) {
        var keys = Object.keys(ctx.variables);
        for (var i = 0; i < keys.length; i++) {
          var k = keys[i];
          window[k] = ctx.variables[k];
        }
        // 也存储到_arguments
        for (var j = 0; j < keys.length; j++) {
          window._arguments[keys[j]] = ctx.variables[keys[j]];
        }
      }
      
      // 设置登录相关信息
      if (ctx.loginInfo) window._loginInfo = ctx.loginInfo;
      if (ctx.loginHeader) window._loginHeader = ctx.loginHeader;
      if (ctx.sourceVariable) window._sourceVariable = ctx.sourceVariable;
      
      // 执行脚本
      var evalResult = eval(script);
      var resultStr = evalResult === undefined ? '' : 
                      evalResult === null ? '' :
                      typeof evalResult === 'object' ? JSON.stringify(evalResult) : String(evalResult);
      
      return JSON.stringify({ success: true, taskId: taskId, result: resultStr });
    } catch (e) {
      console.log('[executeScript] Error:', e);
      return JSON.stringify({ success: false, taskId: taskId, error: e.message || String(e) });
    }
  };

  // ========== 获取任务结果 ==========
  window.getTaskResult = function(taskId) {
    var result = window.rhinoSandbox.results[taskId];
    if (result) {
      delete window.rhinoSandbox.results[taskId];
      return JSON.stringify(result);
    }
    return JSON.stringify({ pending: true });
  };

  // ========== 获取沙箱状态 ==========
  window.getSandboxStatus = function() {
    return JSON.stringify({
      ready: window.rhinoSandbox.ready,
      cheerpjReady: false,
      rhinoReady: true,
      error: window.rhinoSandbox.error,
      pendingCount: window.rhinoSandbox.pendingTasks.length
    });
  };

  // ========== 初始化完成 ==========
  window.rhinoSandbox.ready = true;
  console.log('[RhinoSandbox] Offline mode initialized via runJavaScript');
})();
`;
  }
  
  /**
   * 获取内联的沙箱HTML（备用方法）
   * 包含所有必要的JS代码，避免外部文件加载问题
   */
  private getSandboxHtml(): string {
    return `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Rhino Sandbox</title>
</head>
<body>
<script>
// ========== 沙箱状态 ==========
window.rhinoSandbox = {
  ready: false,
  mode: 'offline',
  error: null,
  pendingTasks: [],
  results: {}
};

// ========== Jsoup实现 ==========
class JsoupDocument {
  constructor(html) {
    this.html = html || '';
    this._doc = null;
    try {
      const parser = new DOMParser();
      this._doc = parser.parseFromString(this.html, 'text/html');
    } catch (e) {}
  }
  
  title() {
    if (this._doc) {
      const el = this._doc.querySelector('title');
      return el ? el.textContent : '';
    }
    const m = this.html.match(/<title[^>]*>([^<]*)<\\/title>/i);
    return m ? m[1] : '';
  }
  
  select(selector) {
    if (!this._doc) return new JsoupElements([]);
    try {
      const els = this._doc.querySelectorAll(selector);
      return new JsoupElements(Array.from(els).map(e => new JsoupElement(e, this)));
    } catch (e) {
      return new JsoupElements([]);
    }
  }
  
  selectFirst(selector) {
    const els = this.select(selector);
    return els.size() > 0 ? els.get(0) : null;
  }
  
  body() {
    if (this._doc && this._doc.body) {
      return new JsoupElement(this._doc.body, this);
    }
    return new JsoupElement(null, this);
  }
  
  text() {
    if (this._doc && this._doc.body) {
      return this._doc.body.textContent || '';
    }
    return this.html.replace(/<[^>]+>/g, '');
  }
  
  html() { return this.html; }
  outerHtml() { return this.html; }
}

class JsoupElement {
  constructor(el, doc) {
    this._el = el;
    this._doc = doc;
  }
  
  text() { return this._el ? (this._el.textContent || '') : ''; }
  html() { return this._el ? (this._el.innerHTML || '') : ''; }
  outerHtml() { return this._el ? (this._el.outerHTML || '') : ''; }
  
  attr(name) {
    if (!this._el) return '';
    if (name === 'href' || name === 'src') {
      return this._el.getAttribute(name) || '';
    }
    return this._el.getAttribute(name) || '';
  }
  
  select(selector) {
    if (!this._el) return new JsoupElements([]);
    try {
      const els = this._el.querySelectorAll(selector);
      return new JsoupElements(Array.from(els).map(e => new JsoupElement(e, this._doc)));
    } catch (e) {
      return new JsoupElements([]);
    }
  }
  
  selectFirst(selector) {
    const els = this.select(selector);
    return els.size() > 0 ? els.get(0) : null;
  }
  
  tagName() { return this._el ? this._el.tagName.toLowerCase() : ''; }
  id() { return this._el ? (this._el.id || '') : ''; }
  className() { return this._el ? (this._el.className || '') : ''; }
}

class JsoupElements {
  constructor(els) { this._els = els || []; }
  size() { return this._els.length; }
  get(i) { return i >= 0 && i < this._els.length ? this._els[i] : null; }
  first() { return this.get(0); }
  last() { return this.get(this._els.length - 1); }
  text() { return this._els.map(e => e.text()).join(' '); }
  
  eachText() {
    const result = [];
    for (let i = 0; i < this._els.length; i++) {
      result.push(this._els[i].text());
    }
    return result;
  }
  
  eachAttr(name) {
    const result = [];
    for (let i = 0; i < this._els.length; i++) {
      result.push(this._els[i].attr(name));
    }
    return result;
  }
  
  select(selector) {
    let all = [];
    for (let i = 0; i < this._els.length; i++) {
      const sub = this._els[i].select(selector);
      all = all.concat(sub._els);
    }
    return new JsoupElements(all);
  }
}

window.Jsoup = {
  parse: function(html) { return new JsoupDocument(html); }
};

// ========== java对象 ==========
window.java = {
  ajax: function(url) { return ''; },
  ajaxAll: function(urls) { return []; },
  connect: function(url) { return { body: '', code: 0 }; },
  post: function(url, body, headers) { return ''; },
  get: function(url, headers) { return ''; },
  put: function(key, value) { window['_var_' + key] = value; },
  getString: function(key) { return window['_var_' + key] || ''; },
  base64Decode: function(str) {
    try { return decodeURIComponent(escape(atob(str))); } catch(e) { return atob(str); }
  },
  base64Encode: function(str) {
    try { return btoa(unescape(encodeURIComponent(str))); } catch(e) { return btoa(str); }
  },
  timeFormat: function(ts, fmt) {
    const d = new Date(typeof ts === 'number' ? ts : parseInt(ts));
    return d.toString();
  },
  log: function(msg) { console.log('[java.log]', msg); },
  logType: function(obj) { console.log('[java.logType]', typeof obj); }
};

// ========== source对象 ==========
window.source = {
  bookSourceUrl: '',
  bookSourceName: '',
  getLoginInfo: function() { return window._loginInfo || ''; },
  getLoginHeader: function() { return window._loginHeader || ''; },
  putLoginInfo: function(info) { window._loginInfo = info; },
  putLoginHeader: function(header) { window._loginHeader = header; },
  getVariable: function() { return window._sourceVariable || ''; },
  setVariable: function(v) { window._sourceVariable = v; }
};

// ========== cookie对象 ==========
window.cookie = {
  getCookie: function(url) { return ''; },
  setCookie: function(url, cookie) {},
  removeCookie: function(url) {},
  clearCookie: function() {}
};

// ========== cache对象 ==========
window.cache = {
  get: function(key) { return window['_cache_' + key] || ''; },
  put: function(key, value, timeout) { window['_cache_' + key] = value; },
  delete: function(key) { delete window['_cache_' + key]; },
  deleteDatabase: function() {}
};

// ========== 执行脚本 ==========
window.executeScript = function(taskId, script, contextJson) {
  try {
    const ctx = contextJson ? SafeUtils.parseObj(contextJson) : {};
    
    // 设置上下文变量
    window.result = ctx.result || '';
    window.baseUrl = ctx.baseUrl || '';
    window.key = ctx.key || '';
    window.page = ctx.page || 1;
    
    if (ctx.loginInfo) window._loginInfo = ctx.loginInfo;
    if (ctx.loginHeader) window._loginHeader = ctx.loginHeader;
    if (ctx.sourceVariable) window._sourceVariable = ctx.sourceVariable;
    
    // 执行脚本
    const evalResult = eval(script);
    const resultStr = evalResult === undefined ? '' : String(evalResult);
    
    return JSON.stringify({ success: true, taskId: taskId, result: resultStr });
  } catch (e) {
    return JSON.stringify({ success: false, taskId: taskId, error: e.message || String(e) });
  }
};

// ========== 获取任务结果 ==========
window.getTaskResult = function(taskId) {
  const result = window.rhinoSandbox.results[taskId];
  if (result) {
    delete window.rhinoSandbox.results[taskId];
    return JSON.stringify(result);
  }
  return JSON.stringify({ pending: true });
};

// ========== 获取沙箱状态 ==========
window.getSandboxStatus = function() {
  return JSON.stringify({
    ready: window.rhinoSandbox.ready,
    cheerpjReady: false,
    rhinoReady: true,
    error: window.rhinoSandbox.error,
    pendingCount: window.rhinoSandbox.pendingTasks.length
  });
};

// ========== 初始化完成 ==========
window.rhinoSandbox.ready = true;
console.log('[RhinoSandbox] Offline mode initialized');
</script>
</body>
</html>`;
  }
  
  /**
   * 等待沙箱就绪
   */
  private async waitForSandboxReady(timeoutMs: number): Promise<boolean> {
    const startTime = Date.now();
    const checkInterval = 500; // 每500ms检查一次
    let checkCount = 0;
    
    while (Date.now() - startTime < timeoutMs) {
      try {
        checkCount++;
        const status = await this.getSandboxStatus();
        
        // 每次检查都输出日志
        if (checkCount <= 5 || checkCount % 10 === 0) {
          logger.debug(TAG, `沙箱状态检查 #${checkCount}: ready=${status.ready}, error=${status.error || 'none'}`);
        }
        
        if (status.ready) {
          logger.info(TAG, `沙箱就绪，共检查${checkCount}次`);
          return true;
        }
        if (status.error) {
          this.initError = status.error;
          logger.error(TAG, `沙箱初始化错误: ${status.error}`);
          return false;
        }
      } catch (e) {
        if (checkCount <= 3) {
          logger.debug(TAG, `沙箱状态检查异常 #${checkCount}: ${String(e)}`);
        }
      }
      
      await this.sleep(checkInterval);
    }
    
    logger.error(TAG, `沙箱初始化超时，共检查${checkCount}次`);
    return false;
  }
  
  /**
   * 获取沙箱状态
   */
  private async getSandboxStatus(): Promise<SandboxStatus> {
    if (!this.webviewController) {
      return {
        ready: false,
        cheerpjReady: false,
        rhinoReady: false,
        error: 'WebView未初始化',
        pendingCount: 0
      };
    }
    
    try {
      const result = await this.webviewController.runJavaScript('typeof getSandboxStatus === "function" ? getSandboxStatus() : JSON.stringify({ready:false,error:"function not defined"})');
      logger.debug(TAG, `runJavaScript原始返回: ${result ? result.substring(0, 200) : 'null/undefined'}`);
      
      if (result && result !== 'null' && result !== 'undefined') {
        // runJavaScript可能返回双重JSON编码的字符串
        let parsed = result;
        // 如果结果是字符串形式的JSON（被引号包裹），需要先解析一次
        if (parsed.startsWith('"') && parsed.endsWith('"')) {
          parsed = SafeUtils.parseObj(parsed);
        }
        const status = SafeUtils.parseObj(parsed) as SandboxStatus;
        return status;
      } else {
        logger.debug(TAG, 'getSandboxStatus返回空结果');
      }
    } catch (e) {
      logger.debug(TAG, `getSandboxStatus执行异常: ${String(e)}`);
    }
    
    return {
      ready: false,
      cheerpjReady: false,
      rhinoReady: false,
      error: null,
      pendingCount: 0
    };
  }
  
  /**
   * 启动状态检查
   */
  private startStatusCheck(): void {
    if (this.statusCheckInterval !== null) {
      return;
    }
    
    // 每5秒检查一次任务结果
    this.statusCheckInterval = setInterval(() => {
      this.checkPendingTasks();
    }, 1000) as number;
  }
  
  /**
   * 检查待处理任务
   */
  private async checkPendingTasks(): Promise<void> {
    if (!this.webviewController || this.pendingTasks.size === 0) {
      return;
    }
    
    const taskIds = Array.from(this.pendingTasks.keys());
    for (let i = 0; i < taskIds.length; i++) {
      const taskId = taskIds[i];
      const task = this.pendingTasks.get(taskId);
      if (!task) continue;
      
      try {
        const resultStr = await this.webviewController.runJavaScript(`getTaskResult('${taskId}')`);
        if (resultStr) {
          const result = SafeUtils.parseObj(resultStr) as RhinoExecuteResult;
          
          if (!result.pending) {
            // 任务已完成
            this.pendingTasks.delete(taskId);
            
            if (task.timeoutId) {
              clearTimeout(task.timeoutId);
            }
            
            if (result.success) {
              task.resolve(result);
            } else {
              task.resolve({
                success: false,
                result: '',
                error: result.error || '执行失败',
                taskId: taskId
              });
            }
          }
        }
      } catch (e) {
        // 忽略单个任务检查错误
      }
    }
  }
  
  /**
   * 执行Rhino脚本
   * 
   * @param script JavaScript代码
   * @param context 执行上下文
   * @param timeout 超时时间（毫秒），默认30秒
   * @returns 执行结果
   */
  async execute(script: string, context: RhinoContext = {}, timeout: number = 30000): Promise<RhinoExecuteResult> {
    // 确保沙箱已初始化
    if (!this.sandboxReady) {
      const initialized = await this.initialize();
      if (!initialized) {
        return {
          success: false,
          result: '',
          error: this.initError || '沙箱初始化失败'
        };
      }
    }
    
    if (!this.webviewController) {
      return {
        success: false,
        result: '',
        error: 'WebView控制器未设置'
      };
    }
    
    // 生成任务ID
    const taskId = `task_${++this.taskIdCounter}_${Date.now()}`;
    
    return new Promise((resolve, reject) => {
      // 创建任务
      const task: PendingTask = {
        taskId,
        script,
        context,
        resolve,
        reject
      };
      
      // 设置超时
      task.timeoutId = setTimeout(() => {
        this.pendingTasks.delete(taskId);
        resolve({
          success: false,
          result: '',
          error: `执行超时(${timeout}ms)`,
          taskId
        });
      }, timeout) as number;
      
      // 添加到待处理列表
      this.pendingTasks.set(taskId, task);
      
      // 执行脚本
      this.executeInSandbox(taskId, script, context).catch((error: Object) => {
        this.pendingTasks.delete(taskId);
        if (task.timeoutId) {
          clearTimeout(task.timeoutId);
        }
        resolve({
          success: false,
          result: '',
          error: String(error),
          taskId
        });
      });
    });
  }
  
  /**
   * 在沙箱中执行脚本
   */
  private async executeInSandbox(taskId: string, script: string, context: RhinoContext): Promise<void> {
    if (!this.webviewController) {
      throw new Error('WebView控制器未设置');
    }
    
    // 转义脚本中的特殊字符
    const escapedScript = this.escapeScript(script);
    const contextJson = JSON.stringify(context);
    
    // 调用沙箱的executeScript函数
    const jsCode = `executeScript('${taskId}', '${escapedScript}', '${this.escapeJson(contextJson)}')`;
    
    try {
      logger.debug(TAG, `执行沙箱脚本，taskId: ${taskId}, 脚本长度: ${script.length}`);
      const result = await this.webviewController.runJavaScript(jsCode);
      logger.debug(TAG, `沙箱脚本执行返回: ${result ? result.substring(0, 500) : 'null'}`);
      
      // 检查是否立即返回了结果
      if (result && result !== 'null' && result !== 'undefined') {
        // runJavaScript可能返回双重JSON编码的字符串
        let parsedResult = result;
        if (parsedResult.startsWith('"') && parsedResult.endsWith('"')) {
          parsedResult = SafeUtils.parseObj(parsedResult);
        }
        const parsed = SafeUtils.parseObj(parsedResult) as RhinoExecuteResult;
        logger.debug(TAG, `解析结果: success=${parsed.success}, result=${parsed.result?.substring(0, 100)}, error=${parsed.error}`);
        
        if (!parsed.pending) {
          // 立即完成
          const task = this.pendingTasks.get(taskId);
          if (task) {
            this.pendingTasks.delete(taskId);
            if (task.timeoutId) {
              clearTimeout(task.timeoutId);
            }
            task.resolve(parsed);
          }
        }
      } else {
        logger.warn(TAG, `沙箱脚本执行返回空结果`);
      }
    } catch (error) {
      logger.error(TAG, `沙箱脚本执行异常: ${String(error)}`);
      throw new Error(String(error));
    }
  }
  
  /**
   * 转义脚本字符串
   */
  private escapeScript(script: string): string {
    return script
      .replace(/\\/g, '\\\\')
      .replace(/'/g, "\\'")
      .replace(/"/g, '\\"')
      .replace(/\n/g, '\\n')
      .replace(/\r/g, '\\r')
      .replace(/\t/g, '\\t');
  }
  
  /**
   * 转义JSON字符串
   */
  private escapeJson(json: string): string {
    return json
      .replace(/\\/g, '\\\\')
      .replace(/'/g, "\\'");
  }
  
  /**
   * 同步执行简单脚本
   * 用于不需要网络请求的简单计算
   */
  async executeSimple(script: string, context: RhinoContext = {}): Promise<string> {
    const result = await this.execute(script, context, 10000);
    return result.success ? result.result : '';
  }
  
  /**
   * 检查沙箱是否就绪
   */
  isSandboxReady(): boolean {
    return this.sandboxReady;
  }
  
  /**
   * 获取初始化错误
   */
  getInitError(): string | null {
    return this.initError;
  }
  
  /**
   * 销毁执行器
   */
  destroy(): void {
    // 停止状态检查
    if (this.statusCheckInterval !== null) {
      clearInterval(this.statusCheckInterval);
      this.statusCheckInterval = null;
    }
    
    // 清理待处理任务
    const destroyTaskIds = Array.from(this.pendingTasks.keys());
    for (let i = 0; i < destroyTaskIds.length; i++) {
      const taskId = destroyTaskIds[i];
      const task = this.pendingTasks.get(taskId);
      if (!task) continue;
      
      if (task.timeoutId) {
        clearTimeout(task.timeoutId);
      }
      task.resolve({
        success: false,
        result: '',
        error: '执行器已销毁',
        taskId: taskId
      });
    }
    this.pendingTasks.clear();
    
    // 重置状态
    this.webviewController = null;
    this.isInitialized = false;
    this.sandboxReady = false;
    this.initError = null;
    this.initPromise = null;
    
    RhinoWasmExecutor.instance = null;
    
    logger.info(TAG, 'Rhino WASM执行器已销毁');
  }
  
  /**
   * 辅助函数：休眠
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

/**
 * 获取Rhino WASM执行器实例
 */
export function getRhinoWasmExecutor(): RhinoWasmExecutor {
  return RhinoWasmExecutor.getInstance();
}

/**
 * 快速执行Rhino脚本
 */
export async function executeRhinoScript(script: string, context?: RhinoContext): Promise<RhinoExecuteResult> {
  const executor = getRhinoWasmExecutor();
  return executor.execute(script, context);
}
