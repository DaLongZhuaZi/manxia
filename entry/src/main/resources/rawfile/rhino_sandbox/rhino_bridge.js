/**
 * Rhino Bridge - 连接CheerpJ/Rhino与ArkTS的桥接层
 * 
 * 功能：
 * 1. 初始化Rhino引擎
 * 2. 注入Legado兼容的Java对象（java.xxx）
 * 3. 执行Rhino脚本并返回结果
 * 4. 提供Jsoup DOM解析能力
 */

// Rhino引擎实例
let rhinoContext = null;
let rhinoScope = null;
let jsoupDocument = null;

// 任务ID计数器
let taskIdCounter = 0;

/**
 * 初始化Rhino Bridge
 */
async function initRhinoBridge() {
    console.log('[RhinoBridge] Initializing Rhino Bridge...');
    
    try {
        // 使用CheerpJ加载Rhino类
        const ContextFactory = await cheerpjRunLibrary('/app/rhino.jar:org.mozilla.javascript.ContextFactory');
        const Context = await cheerpjRunLibrary('/app/rhino.jar:org.mozilla.javascript.Context');
        const ScriptableObject = await cheerpjRunLibrary('/app/rhino.jar:org.mozilla.javascript.ScriptableObject');
        
        // 创建Rhino上下文
        rhinoContext = Context.enter();
        
        // 设置优化级别为-1（解释模式，兼容性最好）
        rhinoContext.setOptimizationLevel(-1);
        
        // 初始化标准对象
        rhinoScope = rhinoContext.initStandardObjects();
        
        // 注入Legado兼容的Java对象
        await injectLegadoObjects();
        
        console.log('[RhinoBridge] Rhino Bridge initialized successfully');
        return true;
        
    } catch (error) {
        console.error('[RhinoBridge] Failed to initialize:', error);
        throw error;
    }
}

/**
 * 注入Legado兼容的Java对象
 * 模拟Android Legado的JsExtensions接口
 */
async function injectLegadoObjects() {
    console.log('[RhinoBridge] Injecting Legado compatible objects...');
    
    // 创建java对象
    const javaObj = {
        // ==================== 网络请求 ====================
        ajax: function(url) {
            return syncHttpRequest(url, 'GET', null, null);
        },
        
        ajaxAll: function(urlList) {
            const results = [];
            for (let i = 0; i < urlList.length; i++) {
                results.push(syncHttpRequest(urlList[i], 'GET', null, null));
            }
            return results;
        },
        
        connect: function(url, header) {
            const headers = header ? JSON.parse(header) : null;
            return {
                body: syncHttpRequest(url, 'GET', null, headers),
                url: url,
                code: 200
            };
        },
        
        get: function(urlOrVar, headers) {
            // 检查是否是变量获取
            if (urlOrVar === 'key') return window._ctx_key || '';
            if (urlOrVar === 'page') return window._ctx_page || 1;
            if (urlOrVar === 'result') return window._ctx_result || '';
            if (urlOrVar === 'baseUrl') return window._ctx_baseUrl || '';
            if (urlOrVar === 'sourceUrl') return window._ctx_sourceUrl || '';
            
            // 否则发起HTTP请求
            return syncHttpRequest(urlOrVar, 'GET', null, headers);
        },
        
        put: function(varName, value) {
            if (varName === 'key') window._ctx_key = value;
            if (varName === 'page') window._ctx_page = value;
            if (varName === 'result') window._ctx_result = value;
            return value;
        },
        
        post: function(url, body, headers) {
            return syncHttpRequest(url, 'POST', body, headers);
        },
        
        head: function(url, headers) {
            return syncHttpRequest(url, 'HEAD', null, headers);
        },
        
        // ==================== WebView ====================
        webView: function(html, url, js) {
            if (html && js) {
                try {
                    const iframe = document.createElement('iframe');
                    iframe.style.display = 'none';
                    document.body.appendChild(iframe);
                    iframe.contentDocument.write(html);
                    const result = iframe.contentWindow.eval(js);
                    document.body.removeChild(iframe);
                    return result ? String(result) : '';
                } catch(e) {
                    console.error('[RhinoBridge] webView error:', e);
                    return '';
                }
            }
            if (url) {
                const resp = syncHttpRequest(url, 'GET', null, null);
                if (js && resp) {
                    try {
                        const iframe = document.createElement('iframe');
                        iframe.style.display = 'none';
                        document.body.appendChild(iframe);
                        iframe.contentDocument.write(resp);
                        const result = iframe.contentWindow.eval(js);
                        document.body.removeChild(iframe);
                        return result ? String(result) : resp;
                    } catch(e) {
                        return resp;
                    }
                }
                return resp;
            }
            return '';
        },
        
        webViewGetSource: function(html, url, js, sourceRegex) { return ''; },
        webViewGetOverrideUrl: function(html, url, js, overrideUrlRegex) { return ''; },
        startBrowser: function(url, title) { },
        startBrowserAwait: function(url, title) { return syncHttpRequest(url, 'GET', null, null); },
        getVerificationCode: function(imageUrl) { return ''; },
        
        // ==================== Cookie管理 ====================
        getCookie: function(tag, key) {
            try {
                const cookies = document.cookie.split(';');
                for (let i = 0; i < cookies.length; i++) {
                    const cookie = cookies[i].trim();
                    if (key) {
                        if (cookie.startsWith(key + '=')) {
                            return cookie.substring(key.length + 1);
                        }
                    }
                }
                return key ? '' : document.cookie;
            } catch(e) { return ''; }
        },
        
        setCookie: function(url, cookie) {
            try {
                document.cookie = cookie;
            } catch(e) { /* ignore */ }
        },
        
        // ==================== 文件操作 ====================
        cacheFile: function(url, saveTime) {
            return syncHttpRequest(url, 'GET', null, null);
        },
        
        downloadFile: function(url) { return ''; },
        
        importScript: function(path) {
            if (path && (path.startsWith('http://') || path.startsWith('https://'))) {
                return syncHttpRequest(path, 'GET', null, null);
            }
            return '';
        },
        
        readTxtFile: function(path) { return ''; },
        
        // ==================== 编码解码 ====================
        base64Decode: function(str, charset) {
            try {
                return decodeURIComponent(escape(atob(str)));
            } catch(e) {
                try { return atob(str); } catch(e2) { return str; }
            }
        },
        
        base64Encode: function(str, flags) {
            try {
                return btoa(unescape(encodeURIComponent(str)));
            } catch(e) {
                try { return btoa(str); } catch(e2) { return str; }
            }
        },
        
        base64DecodeToByteArray: function(str, flags) {
            try {
                const binary = atob(str);
                const bytes = new Uint8Array(binary.length);
                for (let i = 0; i < binary.length; i++) {
                    bytes[i] = binary.charCodeAt(i);
                }
                return Array.from(bytes);
            } catch(e) { return []; }
        },
        
        hexDecodeToByteArray: function(hex) {
            const bytes = [];
            for (let i = 0; i < hex.length; i += 2) {
                bytes.push(parseInt(hex.substr(i, 2), 16));
            }
            return bytes;
        },
        
        hexDecodeToString: function(hex) {
            let str = '';
            for (let i = 0; i < hex.length; i += 2) {
                str += String.fromCharCode(parseInt(hex.substr(i, 2), 16));
            }
            return str;
        },
        
        hexEncodeToString: function(utf8) {
            let hex = '';
            for (let i = 0; i < utf8.length; i++) {
                hex += utf8.charCodeAt(i).toString(16).padStart(2, '0');
            }
            return hex;
        },
        
        // ==================== 加密 ====================
        md5Encode: async function(str) {
            const encoder = new TextEncoder();
            const data = encoder.encode(str);
            const hashBuffer = await crypto.subtle.digest('MD5', data).catch(() => null);
            if (!hashBuffer) {
                // MD5 fallback - 简单哈希
                return simpleHash(str);
            }
            const hashArray = Array.from(new Uint8Array(hashBuffer));
            return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
        },
        
        md5Encode16: async function(str) {
            const full = await this.md5Encode(str);
            return full.substring(8, 24);
        },
        
        // ==================== 工具函数 ====================
        timeFormat: function(timestamp) {
            const d = new Date(typeof timestamp === 'number' ? timestamp : parseInt(timestamp));
            return d.getFullYear() + '/' +
                   String(d.getMonth() + 1).padStart(2, '0') + '/' +
                   String(d.getDate()).padStart(2, '0') + ' ' +
                   String(d.getHours()).padStart(2, '0') + ':' +
                   String(d.getMinutes()).padStart(2, '0');
        },
        
        timeFormatUTC: function(timestamp, format, sh) {
            const d = new Date(typeof timestamp === 'number' ? timestamp : parseInt(timestamp));
            if (sh) d.setHours(d.getHours() + sh);
            return this.timeFormat(d.getTime());
        },
        
        encodeURI: function(str) {
            return encodeURIComponent(str);
        },
        
        decodeURI: function(str) {
            return decodeURIComponent(str);
        },
        
        htmlFormat: function(str) {
            return str.replace(/&nbsp;/g, ' ')
                      .replace(/&lt;/g, '<')
                      .replace(/&gt;/g, '>')
                      .replace(/&amp;/g, '&')
                      .replace(/&quot;/g, '"')
                      .replace(/<br\s*\/?>/gi, '\n')
                      .replace(/<p>/gi, '\n')
                      .replace(/<\/p>/gi, '')
                      .replace(/<[^>]+>/g, '');
        },
        
        // 繁简转换（简化实现）
        t2s: function(text) { return text; },
        s2t: function(text) { return text; },
        
        // UUID生成
        randomUUID: function() {
            return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
                const r = Math.random() * 16 | 0;
                const v = c === 'x' ? r : (r & 0x3 | 0x8);
                return v.toString(16);
            });
        },
        
        // 字符串分割
        splitNotBlank: function(str, regex) {
            if (!str) return [];
            const parts = str.split(new RegExp(regex));
            return parts.filter(p => p && p.trim().length > 0);
        },
        
        // 日志
        log: function(msg) {
            console.log('[Rhino]', msg);
            return msg;
        },
        
        logType: function(obj) {
            const type = typeof obj;
            console.log('[Rhino] Type:', type);
            return type;
        }
    };
    
    // 将java对象注入到Rhino作用域
    if (rhinoScope) {
        // 使用CheerpJ的方式注入
        const NativeObject = await cheerpjRunLibrary('/app/rhino.jar:org.mozilla.javascript.NativeObject');
        
        // 创建JavaScript对象并注入
        rhinoContext.evaluateString(rhinoScope, `
            var java = ${JSON.stringify(javaObj)};
        `, 'inject', 1, null);
    }
    
    // 同时在window上设置，供直接调用
    window.java = javaObj;
    
    // 创建source对象
    window.source = {
        _key: '',
        _variable: '',
        _loginInfo: '',
        _loginHeader: '',
        
        getKey: function() { return this._key; },
        bookSourceUrl: '',
        bookSourceName: '',
        
        getVariable: function() { return this._variable; },
        setVariable: function(value) { this._variable = value; return value; },
        
        getLoginInfo: function() { return this._loginInfo; },
        getLoginInfoMap: function() {
            try { return this._loginInfo ? JSON.parse(this._loginInfo) : {}; }
            catch(e) { return {}; }
        },
        putLoginInfo: function(info) {
            this._loginInfo = typeof info === 'string' ? info : JSON.stringify(info);
            return info;
        },
        
        getLoginHeader: function() { return this._loginHeader; },
        getLoginHeaderMap: function() {
            try { return this._loginHeader ? JSON.parse(this._loginHeader) : {}; }
            catch(e) { return {}; }
        },
        putLoginHeader: function(header) {
            this._loginHeader = typeof header === 'string' ? header : JSON.stringify(header);
            return header;
        },
        removeLoginHeader: function() { this._loginHeader = ''; },
        
        getHeaderMap: function() { return {}; },
        put: function(key, value) { this['_data_' + key] = value; return value; },
        get: function(key) { return this['_data_' + key] || ''; }
    };
    
    // 创建book对象
    window.book = {
        name: '',
        author: '',
        bookUrl: '',
        tocUrl: '',
        durChapterIndex: 0,
        durChapterTitle: '',
        _variables: {},
        
        getVariable: function(key) {
            if (key) return this._variables[key] || '';
            return JSON.stringify(this._variables);
        },
        putVariable: function(key, value) {
            this._variables[key] = value;
            return value;
        }
    };
    
    // 创建chapter对象
    window.chapter = {
        index: 0,
        title: '',
        url: '',
        isVip: false,
        isPay: false,
        _variables: {},
        
        getVariable: function(key) { return this._variables[key] || ''; },
        putVariable: function(key, value) { this._variables[key] = value; return value; }
    };
    
    // 创建cookie对象
    window.cookie = {
        _store: {},
        getCookie: function(url) { return this._store[url] || document.cookie || ''; },
        setCookie: function(url, value) { this._store[url] = value; },
        removeCookie: function(url) { delete this._store[url]; }
    };
    
    // 创建cache对象
    window.cache = {
        _store: {},
        get: function(key) { return this._store[key] || ''; },
        put: function(key, value) { this._store[key] = value; return value; },
        getMemory: function(key) { return this._store['mem_' + key] || ''; },
        putMemory: function(key, value) { this._store['mem_' + key] = value; return value; },
        delete: function(key) { delete this._store[key]; },
        deleteMemory: function(key) { delete this._store['mem_' + key]; }
    };
    
    // JavaImporter polyfill
    window.JavaImporter = function() { return {}; };
    
    // Packages polyfill
    window.Packages = new Proxy({}, {
        get: function(target, prop) {
            return new Proxy({}, {
                get: function(t, p) { return function() { return ''; }; }
            });
        }
    });
    
    console.log('[RhinoBridge] Legado objects injected successfully');
}

/**
 * 同步HTTP请求
 */
function syncHttpRequest(url, method, body, headers) {
    try {
        const xhr = new XMLHttpRequest();
        xhr.open(method || 'GET', url, false); // false = 同步
        xhr.timeout = 30000;
        
        if (headers) {
            for (const key in headers) {
                if (headers.hasOwnProperty(key)) {
                    xhr.setRequestHeader(key, headers[key]);
                }
            }
        }
        
        if (!headers || !headers['User-Agent']) {
            xhr.setRequestHeader('User-Agent', 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36');
        }
        
        xhr.send(body || null);
        return xhr.responseText;
        
    } catch(e) {
        console.error('[RhinoBridge] HTTP request error:', e);
        return '';
    }
}

/**
 * 简单哈希函数（MD5 fallback）
 */
function simpleHash(str) {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
        const char = str.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash;
    }
    return Math.abs(hash).toString(16).padStart(32, '0');
}

/**
 * 执行Rhino脚本
 */
async function executeRhinoScript(taskId, script, context) {
    console.log(`[RhinoBridge] Executing script, taskId: ${taskId}`);
    
    try {
        // 设置上下文变量
        if (context) {
            window._ctx_result = context.result || '';
            window._ctx_baseUrl = context.baseUrl || '';
            window._ctx_sourceUrl = context.sourceUrl || context.baseUrl || '';
            window._ctx_key = context.key || '';
            window._ctx_page = context.page || 1;
            
            // 更新source对象
            if (window.source) {
                window.source._key = context.sourceUrl || context.baseUrl || '';
                window.source.bookSourceUrl = context.sourceUrl || context.baseUrl || '';
            }
            
            // 更新book对象
            if (context.book && window.book) {
                Object.assign(window.book, context.book);
            }
            
            // 更新chapter对象
            if (context.chapter && window.chapter) {
                Object.assign(window.chapter, context.chapter);
            }
            
            // 设置自定义变量
            if (context.variables) {
                for (const key in context.variables) {
                    window[key] = context.variables[key];
                }
            }
        }
        
        // 构建完整脚本
        const fullScript = `
            var result = ${JSON.stringify(window._ctx_result || '')};
            var baseUrl = ${JSON.stringify(window._ctx_baseUrl || '')};
            var sourceUrl = ${JSON.stringify(window._ctx_sourceUrl || '')};
            var key = ${JSON.stringify(window._ctx_key || '')};
            var page = ${window._ctx_page || 1};
            
            (function() {
                try {
                    ${script}
                } catch(e) {
                    return 'ERROR:' + e.message;
                }
            })()
        `;
        
        let result;
        
        if (rhinoContext && rhinoScope) {
            // 使用Rhino执行
            result = rhinoContext.evaluateString(rhinoScope, fullScript, 'script', 1, null);
        } else {
            // 降级到eval执行
            result = eval(fullScript);
        }
        
        // 处理结果
        const resultStr = result !== undefined && result !== null ? String(result) : '';
        
        // 存储结果
        window.rhinoSandbox.results[taskId] = {
            success: true,
            taskId: taskId,
            result: resultStr
        };
        
        // 通知ArkTS
        notifyArkTS('taskComplete', {
            taskId: taskId,
            success: true,
            result: resultStr
        });
        
        return resultStr;
        
    } catch (error) {
        const errorMsg = error.message || String(error);
        console.error(`[RhinoBridge] Script execution error:`, error);
        
        // 存储错误结果
        window.rhinoSandbox.results[taskId] = {
            success: false,
            taskId: taskId,
            error: errorMsg
        };
        
        // 通知ArkTS
        notifyArkTS('taskComplete', {
            taskId: taskId,
            success: false,
            error: errorMsg
        });
        
        throw error;
    }
}

// 导出函数
window.initRhinoBridge = initRhinoBridge;
window.executeRhinoScript = executeRhinoScript;
