/**
 * Jsoup纯JavaScript实现
 * 
 * 提供与Java Jsoup库兼容的DOM解析API
 * 用于离线模式下的HTML解析
 */

(function(global) {
    'use strict';

    /**
     * Jsoup主类
     */
    class Jsoup {
        /**
         * 解析HTML字符串
         * @param {string} html HTML内容
         * @returns {Document} 文档对象
         */
        static parse(html) {
            return new JsoupDocument(html);
        }

        /**
         * 解析HTML片段
         * @param {string} html HTML片段
         * @param {string} baseUri 基础URI
         * @returns {Document} 文档对象
         */
        static parseBodyFragment(html, baseUri) {
            const doc = new JsoupDocument(`<html><body>${html}</body></html>`);
            doc.baseUri = baseUri || '';
            return doc;
        }

        /**
         * 连接到URL（模拟，实际发起请求）
         * @param {string} url URL地址
         * @returns {Connection} 连接对象
         */
        static connect(url) {
            return new JsoupConnection(url);
        }

        /**
         * 清理HTML
         * @param {string} html HTML内容
         * @param {Whitelist} whitelist 白名单
         * @returns {string} 清理后的HTML
         */
        static clean(html, whitelist) {
            // 简单实现：移除script和style标签
            return html
                .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '')
                .replace(/<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>/gi, '')
                .replace(/on\w+="[^"]*"/gi, '')
                .replace(/on\w+='[^']*'/gi, '');
        }
    }

    /**
     * Jsoup文档类
     */
    class JsoupDocument {
        constructor(html) {
            this.html = html || '';
            this.baseUri = '';
            this._doc = null;
            this._parseHtml();
        }

        _parseHtml() {
            // 使用DOMParser解析HTML
            try {
                const parser = new DOMParser();
                this._doc = parser.parseFromString(this.html, 'text/html');
            } catch (e) {
                // 降级处理
                this._doc = null;
            }
        }

        /**
         * 获取标题
         */
        title() {
            if (this._doc) {
                const titleEl = this._doc.querySelector('title');
                return titleEl ? titleEl.textContent : '';
            }
            const match = this.html.match(/<title[^>]*>([^<]*)<\/title>/i);
            return match ? match[1] : '';
        }

        /**
         * 获取body元素
         */
        body() {
            if (this._doc) {
                return new JsoupElement(this._doc.body, this);
            }
            const match = this.html.match(/<body[^>]*>([\s\S]*)<\/body>/i);
            const bodyHtml = match ? match[1] : this.html;
            return new JsoupElement(null, this, bodyHtml, 'body');
        }

        /**
         * 获取head元素
         */
        head() {
            if (this._doc) {
                return new JsoupElement(this._doc.head, this);
            }
            const match = this.html.match(/<head[^>]*>([\s\S]*)<\/head>/i);
            const headHtml = match ? match[1] : '';
            return new JsoupElement(null, this, headHtml, 'head');
        }

        /**
         * CSS选择器查询
         */
        select(cssQuery) {
            if (this._doc) {
                try {
                    const elements = this._doc.querySelectorAll(cssQuery);
                    return new JsoupElements(Array.from(elements), this);
                } catch (e) {
                    return new JsoupElements([], this);
                }
            }
            return this._selectFromHtml(cssQuery);
        }

        /**
         * 从HTML字符串中选择元素（降级方案）
         */
        _selectFromHtml(cssQuery) {
            // 简单的CSS选择器解析
            const elements = [];
            
            // 处理标签选择器
            const tagMatch = cssQuery.match(/^(\w+)$/);
            if (tagMatch) {
                const tagName = tagMatch[1];
                const regex = new RegExp(`<${tagName}[^>]*>([\\s\\S]*?)<\\/${tagName}>`, 'gi');
                let match;
                while ((match = regex.exec(this.html)) !== null) {
                    elements.push(new JsoupElement(null, this, match[0], tagName));
                }
            }
            
            // 处理class选择器
            const classMatch = cssQuery.match(/^\.(\w+)$/);
            if (classMatch) {
                const className = classMatch[1];
                const regex = new RegExp(`<(\\w+)[^>]*class="[^"]*\\b${className}\\b[^"]*"[^>]*>([\\s\\S]*?)<\\/\\1>`, 'gi');
                let match;
                while ((match = regex.exec(this.html)) !== null) {
                    elements.push(new JsoupElement(null, this, match[0], match[1]));
                }
            }
            
            // 处理ID选择器
            const idMatch = cssQuery.match(/^#(\w+)$/);
            if (idMatch) {
                const id = idMatch[1];
                const regex = new RegExp(`<(\\w+)[^>]*id="${id}"[^>]*>([\\s\\S]*?)<\\/\\1>`, 'gi');
                let match;
                while ((match = regex.exec(this.html)) !== null) {
                    elements.push(new JsoupElement(null, this, match[0], match[1]));
                }
            }
            
            return new JsoupElements(elements, this);
        }

        /**
         * 获取第一个匹配元素
         */
        selectFirst(cssQuery) {
            const elements = this.select(cssQuery);
            return elements.first();
        }

        /**
         * 根据ID获取元素
         */
        getElementById(id) {
            if (this._doc) {
                const el = this._doc.getElementById(id);
                return el ? new JsoupElement(el, this) : null;
            }
            return this.selectFirst('#' + id);
        }

        /**
         * 根据标签名获取元素
         */
        getElementsByTag(tagName) {
            return this.select(tagName);
        }

        /**
         * 根据class获取元素
         */
        getElementsByClass(className) {
            return this.select('.' + className);
        }

        /**
         * 根据属性获取元素
         */
        getElementsByAttribute(attrName) {
            if (this._doc) {
                const elements = this._doc.querySelectorAll(`[${attrName}]`);
                return new JsoupElements(Array.from(elements), this);
            }
            return new JsoupElements([], this);
        }

        /**
         * 获取外部HTML
         */
        outerHtml() {
            return this.html;
        }

        /**
         * 获取内部HTML
         */
        html() {
            return this.body().html();
        }

        /**
         * 获取文本内容
         */
        text() {
            return this.body().text();
        }

        /**
         * 转换为字符串
         */
        toString() {
            return this.html;
        }
    }

    /**
     * Jsoup元素类
     */
    class JsoupElement {
        constructor(nativeElement, doc, htmlContent, tagName) {
            this._el = nativeElement;
            this._doc = doc;
            this._html = htmlContent || '';
            this._tagName = tagName || '';
        }

        /**
         * 获取标签名
         */
        tagName() {
            if (this._el) {
                return this._el.tagName.toLowerCase();
            }
            return this._tagName.toLowerCase();
        }

        /**
         * 获取ID
         */
        id() {
            return this.attr('id');
        }

        /**
         * 获取class名
         */
        className() {
            return this.attr('class');
        }

        /**
         * 检查是否有class
         */
        hasClass(className) {
            const classes = this.className().split(/\s+/);
            return classes.includes(className);
        }

        /**
         * 获取属性值
         */
        attr(attrName) {
            if (this._el) {
                return this._el.getAttribute(attrName) || '';
            }
            // 从HTML字符串中提取属性
            const regex = new RegExp(`${attrName}=["']([^"']*)["']`, 'i');
            const match = this._html.match(regex);
            return match ? match[1] : '';
        }

        /**
         * 检查是否有属性
         */
        hasAttr(attrName) {
            if (this._el) {
                return this._el.hasAttribute(attrName);
            }
            const regex = new RegExp(`\\s${attrName}[=\\s>]`, 'i');
            return regex.test(this._html);
        }

        /**
         * 获取绝对URL
         */
        absUrl(attrName) {
            const url = this.attr(attrName);
            if (!url) return '';
            if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('//')) {
                return url;
            }
            const baseUri = this._doc?.baseUri || '';
            if (!baseUri) return url;
            try {
                return new URL(url, baseUri).href;
            } catch (e) {
                return url;
            }
        }

        /**
         * 获取文本内容
         */
        text() {
            if (this._el) {
                return this._el.textContent || '';
            }
            // 从HTML中提取文本
            return this._html
                .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '')
                .replace(/<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>/gi, '')
                .replace(/<[^>]+>/g, '')
                .replace(/&nbsp;/g, ' ')
                .replace(/&lt;/g, '<')
                .replace(/&gt;/g, '>')
                .replace(/&amp;/g, '&')
                .replace(/&quot;/g, '"')
                .replace(/\s+/g, ' ')
                .trim();
        }

        /**
         * 获取自身文本（不含子元素）
         */
        ownText() {
            if (this._el) {
                let text = '';
                for (const node of this._el.childNodes) {
                    if (node.nodeType === Node.TEXT_NODE) {
                        text += node.textContent;
                    }
                }
                return text.trim();
            }
            return this.text();
        }

        /**
         * 获取内部HTML
         */
        html() {
            if (this._el) {
                return this._el.innerHTML || '';
            }
            // 提取标签内的内容
            const match = this._html.match(/<[^>]+>([\s\S]*)<\/[^>]+>$/);
            return match ? match[1] : this._html;
        }

        /**
         * 获取外部HTML
         */
        outerHtml() {
            if (this._el) {
                return this._el.outerHTML || '';
            }
            return this._html;
        }

        /**
         * CSS选择器查询
         */
        select(cssQuery) {
            if (this._el) {
                try {
                    const elements = this._el.querySelectorAll(cssQuery);
                    return new JsoupElements(Array.from(elements), this._doc);
                } catch (e) {
                    return new JsoupElements([], this._doc);
                }
            }
            // 降级处理
            const tempDoc = new JsoupDocument(this._html);
            return tempDoc.select(cssQuery);
        }

        /**
         * 获取第一个匹配元素
         */
        selectFirst(cssQuery) {
            const elements = this.select(cssQuery);
            return elements.first();
        }

        /**
         * 获取子元素
         */
        children() {
            if (this._el) {
                return new JsoupElements(Array.from(this._el.children), this._doc);
            }
            return new JsoupElements([], this._doc);
        }

        /**
         * 获取子元素数量
         */
        childrenSize() {
            if (this._el) {
                return this._el.children.length;
            }
            return 0;
        }

        /**
         * 获取第一个子元素
         */
        firstElementChild() {
            if (this._el && this._el.firstElementChild) {
                return new JsoupElement(this._el.firstElementChild, this._doc);
            }
            return null;
        }

        /**
         * 获取最后一个子元素
         */
        lastElementChild() {
            if (this._el && this._el.lastElementChild) {
                return new JsoupElement(this._el.lastElementChild, this._doc);
            }
            return null;
        }

        /**
         * 获取父元素
         */
        parent() {
            if (this._el && this._el.parentElement) {
                return new JsoupElement(this._el.parentElement, this._doc);
            }
            return null;
        }

        /**
         * 获取下一个兄弟元素
         */
        nextElementSibling() {
            if (this._el && this._el.nextElementSibling) {
                return new JsoupElement(this._el.nextElementSibling, this._doc);
            }
            return null;
        }

        /**
         * 获取上一个兄弟元素
         */
        previousElementSibling() {
            if (this._el && this._el.previousElementSibling) {
                return new JsoupElement(this._el.previousElementSibling, this._doc);
            }
            return null;
        }

        /**
         * 根据标签名获取元素
         */
        getElementsByTag(tagName) {
            return this.select(tagName);
        }

        /**
         * 根据class获取元素
         */
        getElementsByClass(className) {
            return this.select('.' + className);
        }

        /**
         * 获取data属性
         */
        data() {
            // 用于script/style标签
            if (this._el) {
                return this._el.textContent || '';
            }
            return this.html();
        }

        /**
         * 获取val（用于input等表单元素）
         */
        val() {
            if (this._el && 'value' in this._el) {
                return this._el.value || '';
            }
            return this.attr('value');
        }

        /**
         * 转换为字符串
         */
        toString() {
            return this.outerHtml();
        }
    }

    /**
     * Jsoup元素集合类
     */
    class JsoupElements {
        constructor(elements, doc) {
            this._elements = elements.map(el => {
                if (el instanceof JsoupElement) {
                    return el;
                }
                return new JsoupElement(el, doc);
            });
            this._doc = doc;
            this.length = this._elements.length;
        }

        /**
         * 获取元素数量
         */
        size() {
            return this._elements.length;
        }

        /**
         * 检查是否为空
         */
        isEmpty() {
            return this._elements.length === 0;
        }

        /**
         * 获取第一个元素
         */
        first() {
            return this._elements.length > 0 ? this._elements[0] : null;
        }

        /**
         * 获取最后一个元素
         */
        last() {
            return this._elements.length > 0 ? this._elements[this._elements.length - 1] : null;
        }

        /**
         * 获取指定索引的元素
         */
        get(index) {
            if (index < 0) {
                index = this._elements.length + index;
            }
            return this._elements[index] || null;
        }

        /**
         * 获取指定索引的元素（别名）
         */
        eq(index) {
            return this.get(index);
        }

        /**
         * 遍历元素
         */
        each(callback) {
            this._elements.forEach((el, index) => {
                callback(el, index);
            });
            return this;
        }

        /**
         * 映射元素
         */
        map(callback) {
            return this._elements.map((el, index) => callback(el, index));
        }

        /**
         * 过滤元素
         */
        filter(callback) {
            const filtered = this._elements.filter((el, index) => callback(el, index));
            return new JsoupElements(filtered, this._doc);
        }

        /**
         * CSS选择器查询
         */
        select(cssQuery) {
            const results = [];
            this._elements.forEach(el => {
                const selected = el.select(cssQuery);
                selected._elements.forEach(s => results.push(s));
            });
            return new JsoupElements(results, this._doc);
        }

        /**
         * 获取属性值
         */
        attr(attrName) {
            const first = this.first();
            return first ? first.attr(attrName) : '';
        }

        /**
         * 检查是否有属性
         */
        hasAttr(attrName) {
            const first = this.first();
            return first ? first.hasAttr(attrName) : false;
        }

        /**
         * 获取文本内容
         */
        text() {
            return this._elements.map(el => el.text()).join(' ');
        }

        /**
         * 获取每个元素的文本
         */
        eachText() {
            return this._elements.map(el => el.text());
        }

        /**
         * 获取内部HTML
         */
        html() {
            const first = this.first();
            return first ? first.html() : '';
        }

        /**
         * 获取外部HTML
         */
        outerHtml() {
            return this._elements.map(el => el.outerHtml()).join('');
        }

        /**
         * 获取属性值数组
         */
        eachAttr(attrName) {
            return this._elements.map(el => el.attr(attrName));
        }

        /**
         * 转换为数组
         */
        toArray() {
            return [...this._elements];
        }

        /**
         * 迭代器支持
         */
        [Symbol.iterator]() {
            return this._elements[Symbol.iterator]();
        }

        /**
         * 转换为字符串
         */
        toString() {
            return this.outerHtml();
        }
    }

    /**
     * Jsoup连接类（用于HTTP请求）
     */
    class JsoupConnection {
        constructor(url) {
            this._url = url;
            this._method = 'GET';
            this._headers = {};
            this._data = {};
            this._timeout = 30000;
            this._followRedirects = true;
            this._ignoreContentType = false;
            this._ignoreHttpErrors = false;
        }

        /**
         * 设置请求方法
         */
        method(method) {
            this._method = method.toUpperCase();
            return this;
        }

        /**
         * 设置请求头
         */
        header(name, value) {
            this._headers[name] = value;
            return this;
        }

        /**
         * 批量设置请求头
         */
        headers(headers) {
            Object.assign(this._headers, headers);
            return this;
        }

        /**
         * 设置User-Agent
         */
        userAgent(userAgent) {
            this._headers['User-Agent'] = userAgent;
            return this;
        }

        /**
         * 设置Referrer
         */
        referrer(referrer) {
            this._headers['Referer'] = referrer;
            return this;
        }

        /**
         * 设置Cookie
         */
        cookie(name, value) {
            const cookies = this._headers['Cookie'] || '';
            this._headers['Cookie'] = cookies ? `${cookies}; ${name}=${value}` : `${name}=${value}`;
            return this;
        }

        /**
         * 批量设置Cookie
         */
        cookies(cookies) {
            for (const name in cookies) {
                this.cookie(name, cookies[name]);
            }
            return this;
        }

        /**
         * 设置请求数据
         */
        data(key, value) {
            if (typeof key === 'object') {
                Object.assign(this._data, key);
            } else {
                this._data[key] = value;
            }
            return this;
        }

        /**
         * 设置请求体
         */
        requestBody(body) {
            this._body = body;
            return this;
        }

        /**
         * 设置超时
         */
        timeout(millis) {
            this._timeout = millis;
            return this;
        }

        /**
         * 设置是否跟随重定向
         */
        followRedirects(follow) {
            this._followRedirects = follow;
            return this;
        }

        /**
         * 忽略内容类型
         */
        ignoreContentType(ignore) {
            this._ignoreContentType = ignore;
            return this;
        }

        /**
         * 忽略HTTP错误
         */
        ignoreHttpErrors(ignore) {
            this._ignoreHttpErrors = ignore;
            return this;
        }

        /**
         * 执行GET请求
         */
        get() {
            this._method = 'GET';
            return this.execute();
        }

        /**
         * 执行POST请求
         */
        post() {
            this._method = 'POST';
            return this.execute();
        }

        /**
         * 执行请求
         */
        execute() {
            return new Promise((resolve, reject) => {
                try {
                    const xhr = new XMLHttpRequest();
                    xhr.open(this._method, this._url, false); // 同步请求
                    xhr.timeout = this._timeout;

                    // 设置请求头
                    for (const name in this._headers) {
                        xhr.setRequestHeader(name, this._headers[name]);
                    }

                    // 准备请求体
                    let body = null;
                    if (this._body) {
                        body = this._body;
                    } else if (Object.keys(this._data).length > 0) {
                        if (this._method === 'POST') {
                            body = new URLSearchParams(this._data).toString();
                            xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
                        }
                    }

                    xhr.send(body);

                    if (xhr.status >= 200 && xhr.status < 400) {
                        const response = new JsoupResponse(xhr);
                        resolve(response);
                    } else if (this._ignoreHttpErrors) {
                        const response = new JsoupResponse(xhr);
                        resolve(response);
                    } else {
                        reject(new Error(`HTTP error: ${xhr.status}`));
                    }
                } catch (e) {
                    reject(e);
                }
            });
        }
    }

    /**
     * Jsoup响应类
     */
    class JsoupResponse {
        constructor(xhr) {
            this._xhr = xhr;
            this._body = xhr.responseText;
            this._statusCode = xhr.status;
            this._statusMessage = xhr.statusText;
            this._url = xhr.responseURL || '';
            this._contentType = xhr.getResponseHeader('Content-Type') || '';
        }

        /**
         * 获取状态码
         */
        statusCode() {
            return this._statusCode;
        }

        /**
         * 获取状态消息
         */
        statusMessage() {
            return this._statusMessage;
        }

        /**
         * 获取URL
         */
        url() {
            return this._url;
        }

        /**
         * 获取内容类型
         */
        contentType() {
            return this._contentType;
        }

        /**
         * 获取响应体
         */
        body() {
            return this._body;
        }

        /**
         * 解析为文档
         */
        parse() {
            const doc = Jsoup.parse(this._body);
            doc.baseUri = this._url;
            return doc;
        }

        /**
         * 获取响应头
         */
        header(name) {
            return this._xhr.getResponseHeader(name) || '';
        }

        /**
         * 获取Cookie
         */
        cookie(name) {
            const cookies = this.header('Set-Cookie');
            if (!cookies) return '';
            const match = cookies.match(new RegExp(`${name}=([^;]+)`));
            return match ? match[1] : '';
        }

        /**
         * 获取所有Cookie
         */
        cookies() {
            const cookies = {};
            const cookieHeader = this.header('Set-Cookie');
            if (cookieHeader) {
                const parts = cookieHeader.split(/[,;]/);
                for (const part of parts) {
                    const match = part.trim().match(/^([^=]+)=(.*)$/);
                    if (match && !['path', 'domain', 'expires', 'max-age', 'secure', 'httponly'].includes(match[1].toLowerCase())) {
                        cookies[match[1]] = match[2];
                    }
                }
            }
            return cookies;
        }
    }

    // 导出到全局
    global.Jsoup = Jsoup;
    global.JsoupDocument = JsoupDocument;
    global.JsoupElement = JsoupElement;
    global.JsoupElements = JsoupElements;
    global.JsoupConnection = JsoupConnection;
    global.JsoupResponse = JsoupResponse;

    console.log('[JsoupImpl] Jsoup JavaScript implementation loaded');

})(typeof window !== 'undefined' ? window : global);
