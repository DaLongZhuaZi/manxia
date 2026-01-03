/**
 * Rhino Offline - 纯JavaScript实现的Legado兼容执行环境
 * 
 * 当CheerpJ不可用时，使用此离线模式
 * 提供与Rhino引擎相同的java.xxx接口
 * 集成Jsoup DOM解析能力
 */

// 上下文变量
window._ctx_result = '';
window._ctx_baseUrl = '';
window._ctx_sourceUrl = '';
window._ctx_key = '';
window._ctx_page = 1;

// Jsoup集成标志
window._jsoupAvailable = typeof Jsoup !== 'undefined';

/**
 * 初始化离线Rhino环境
 */
async function initOfflineRhino() {
    console.log('[RhinoOffline] Initializing offline Rhino environment...');
    
    // 创建java对象
    window.java = {
        // ==================== 网络请求 ====================
        ajax: function(url) {
            const urlStr = Array.isArray(url) ? url[0] : url;
            return syncHttpRequest(urlStr, 'GET', null, null);
        },
        
        ajaxAll: function(urlList) {
            const results = [];
            for (let i = 0; i < urlList.length; i++) {
                results.push(syncHttpRequest(urlList[i], 'GET', null, null));
            }
            return results;
        },
        
        connect: function(url, header) {
            const headers = header ? (typeof header === 'string' ? JSON.parse(header) : header) : null;
            const body = syncHttpRequest(url, 'GET', null, headers);
            return {
                body: body,
                url: url,
                code: body ? 200 : 0,
                headers: ''
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
            const body = syncHttpRequest(urlOrVar, 'GET', null, headers);
            return {
                body: body,
                url: urlOrVar,
                code: body ? 200 : 0
            };
        },
        
        put: function(varName, value) {
            if (varName === 'key') { window._ctx_key = value; }
            if (varName === 'page') { window._ctx_page = value; }
            if (varName === 'result') { window._ctx_result = value; }
            return value;
        },
        
        post: function(url, body, headers) {
            const respBody = syncHttpRequest(url, 'POST', body, headers);
            return {
                body: respBody,
                url: url,
                code: respBody ? 200 : 0
            };
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
                    console.error('[RhinoOffline] webView error:', e);
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
        startBrowserAwait: function(url, title) { 
            return { body: syncHttpRequest(url, 'GET', null, null), url: url, code: 200 };
        },
        getVerificationCode: function(imageUrl) { return ''; },
        
        // ==================== Cookie管理 ====================
        getCookie: function(tag, key) {
            try {
                if (window.cookie && window.cookie._store[tag]) {
                    const cookies = window.cookie._store[tag];
                    if (key) {
                        const parts = cookies.split(';');
                        for (let i = 0; i < parts.length; i++) {
                            const part = parts[i].trim();
                            if (part.startsWith(key + '=')) {
                                return part.substring(key.length + 1);
                            }
                        }
                        return '';
                    }
                    return cookies;
                }
                return document.cookie || '';
            } catch(e) { return ''; }
        },
        
        setCookie: function(url, cookie) {
            if (window.cookie) {
                window.cookie._store[url] = cookie;
            }
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
        md5Encode: function(str) {
            // 简单哈希实现
            return simpleHash(str);
        },
        
        md5Encode16: function(str) {
            const full = this.md5Encode(str);
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
        
        // 获取绝对URL
        getAbsoluteURL: function(baseUrl, relativePath) {
            if (!relativePath) return baseUrl;
            if (relativePath.startsWith('http://') || relativePath.startsWith('https://')) {
                return relativePath;
            }
            try {
                return new URL(relativePath, baseUrl).href;
            } catch(e) {
                return relativePath;
            }
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
        },
        
        // 字符串转字节
        strToBytes: function(str, charset) {
            const encoder = new TextEncoder();
            return Array.from(encoder.encode(str));
        },
        
        // 字节转字符串
        bytesToStr: function(bytes, charset) {
            const decoder = new TextDecoder(charset || 'utf-8');
            return decoder.decode(new Uint8Array(bytes));
        },
        
        // ==================== Jsoup DOM解析 ====================
        // 解析HTML
        parseHtml: function(html, baseUrl) {
            if (typeof Jsoup !== 'undefined') {
                const doc = Jsoup.parse(html);
                if (baseUrl) doc.baseUri = baseUrl;
                return doc;
            }
            // 降级处理
            return {
                select: function(cssQuery) { return { first: function() { return null; }, text: function() { return ''; } }; },
                text: function() { return html.replace(/<[^>]+>/g, ''); },
                html: function() { return html; }
            };
        },
        
        // 使用CSS选择器获取元素
        selectElements: function(html, cssQuery) {
            if (typeof Jsoup !== 'undefined') {
                const doc = Jsoup.parse(html);
                return doc.select(cssQuery);
            }
            return { first: function() { return null; }, text: function() { return ''; }, size: function() { return 0; } };
        },
        
        // 获取元素文本
        selectText: function(html, cssQuery) {
            if (typeof Jsoup !== 'undefined') {
                const doc = Jsoup.parse(html);
                const el = doc.selectFirst(cssQuery);
                return el ? el.text() : '';
            }
            return '';
        },
        
        // 获取元素属性
        selectAttr: function(html, cssQuery, attrName) {
            if (typeof Jsoup !== 'undefined') {
                const doc = Jsoup.parse(html);
                const el = doc.selectFirst(cssQuery);
                return el ? el.attr(attrName) : '';
            }
            return '';
        },
        
        // 获取所有匹配元素的文本列表
        selectTextList: function(html, cssQuery) {
            if (typeof Jsoup !== 'undefined') {
                const doc = Jsoup.parse(html);
                const elements = doc.select(cssQuery);
                return elements.eachText();
            }
            return [];
        },
        
        // 获取所有匹配元素的属性列表
        selectAttrList: function(html, cssQuery, attrName) {
            if (typeof Jsoup !== 'undefined') {
                const doc = Jsoup.parse(html);
                const elements = doc.select(cssQuery);
                return elements.eachAttr(attrName);
            }
            return [];
        },
        
        // 清理HTML
        cleanHtml: function(html) {
            if (typeof Jsoup !== 'undefined') {
                return Jsoup.clean(html);
            }
            return html.replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '')
                       .replace(/<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>/gi, '');
        }
    };
    
    // 创建org.jsoup包装（模拟Java包结构）
    window.org = window.org || {};
    window.org.jsoup = {
        Jsoup: typeof Jsoup !== 'undefined' ? Jsoup : {
            parse: function(html) { return window.java.parseHtml(html); },
            connect: function(url) { 
                return {
                    get: function() {
                        const body = syncHttpRequest(url, 'GET', null, null);
                        return { parse: function() { return window.java.parseHtml(body, url); } };
                    }
                };
            }
        }
    };
    
    // 创建source对象
    window.source = {
        _key: '',
        _variable: '',
        _loginInfo: '',
        _loginHeader: '',
        bookSourceUrl: '',
        bookSourceName: '',
        
        getKey: function() { return this._key || this.bookSourceUrl; },
        
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
        getCookie: function(url) { return this._store[url] || ''; },
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
    
    console.log('[RhinoOffline] Offline Rhino environment initialized successfully');
    return true;
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
            const headerObj = typeof headers === 'string' ? JSON.parse(headers) : headers;
            for (const key in headerObj) {
                if (headerObj.hasOwnProperty(key)) {
                    xhr.setRequestHeader(key, headerObj[key]);
                }
            }
        }
        
        if (!headers || (!headers['User-Agent'] && !headers['user-agent'])) {
            xhr.setRequestHeader('User-Agent', 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36');
        }
        
        xhr.send(body || null);
        return xhr.responseText;
        
    } catch(e) {
        console.error('[RhinoOffline] HTTP request error:', e);
        return '';
    }
}

/**
 * 简单哈希函数
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
 * 执行离线脚本
 */
async function executeOfflineScript(taskId, script, context) {
    console.log(`[RhinoOffline] Executing script, taskId: ${taskId}`);
    
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
                if (context.sourceVariable) {
                    window.source._variable = context.sourceVariable;
                }
                if (context.loginInfo) {
                    window.source._loginInfo = context.loginInfo;
                }
                if (context.loginHeader) {
                    window.source._loginHeader = context.loginHeader;
                }
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
        // 处理result变量 - 如果是JSON则解析为对象
        let resultVar;
        const resultStr = window._ctx_result || '';
        if (resultStr.startsWith('{') || resultStr.startsWith('[')) {
            resultVar = `var result = (function() { try { return JSON.parse(${JSON.stringify(resultStr)}); } catch(e) { return ${JSON.stringify(resultStr)}; } })();`;
        } else {
            resultVar = `var result = ${JSON.stringify(resultStr)};`;
        }
        
        const fullScript = `
            ${resultVar}
            var baseUrl = ${JSON.stringify(window._ctx_baseUrl || '')};
            var sourceUrl = ${JSON.stringify(window._ctx_sourceUrl || '')};
            var key = ${JSON.stringify(window._ctx_key || '')};
            var page = ${window._ctx_page || 1};
            
            (function() {
                try {
                    return (function() {
                        ${script}
                    })();
                } catch(e) {
                    return 'ERROR:' + e.message;
                }
            })()
        `;
        
        // 执行脚本
        const result = eval(fullScript);
        
        // 处理结果
        const resultString = result !== undefined && result !== null ? String(result) : '';
        
        // 检查是否是错误
        if (resultString.startsWith('ERROR:')) {
            throw new Error(resultString.substring(6));
        }
        
        // 存储结果
        window.rhinoSandbox.results[taskId] = {
            success: true,
            taskId: taskId,
            result: resultString
        };
        
        // 通知ArkTS
        if (typeof notifyArkTS === 'function') {
            notifyArkTS('taskComplete', {
                taskId: taskId,
                success: true,
                result: resultString
            });
        }
        
        return resultString;
        
    } catch (error) {
        const errorMsg = error.message || String(error);
        console.error(`[RhinoOffline] Script execution error:`, error);
        
        // 存储错误结果
        window.rhinoSandbox.results[taskId] = {
            success: false,
            taskId: taskId,
            error: errorMsg
        };
        
        // 通知ArkTS
        if (typeof notifyArkTS === 'function') {
            notifyArkTS('taskComplete', {
                taskId: taskId,
                success: false,
                error: errorMsg
            });
        }
        
        throw error;
    }
}

// 导出函数
window.initOfflineRhino = initOfflineRhino;
window.executeOfflineScript = executeOfflineScript;
