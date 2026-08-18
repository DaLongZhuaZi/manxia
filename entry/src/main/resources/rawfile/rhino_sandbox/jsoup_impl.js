/**
 * Jsoup纯JavaScript实现
 * 
 * 提供与Java Jsoup库兼容的DOM解析API
 * 用于离线模式下的HTML解析
 */

(function(global) {
    'use strict';

    // Jsoup 1.16.2 text projection primitives. textContent is not equivalent
    // to Element.text(): whitespace is normalized and block/br boundaries are
    // represented by an ASCII space.
    function legadoIsActuallyWhitespace(code) {
        return code === 32 || code === 9 || code === 10 || code === 12 ||
            code === 13 || code === 160;
    }

    function legadoCreateTextAccumulator() {
        return { value: '', lastCharIsSpace: false };
    }

    function legadoAppendText(accumulator, value, preserveWhitespace) {
        const text = String(value || '');
        if (!text) return;
        if (preserveWhitespace) {
            accumulator.value += text;
            accumulator.lastCharIsSpace = text.charAt(text.length - 1) === ' ';
            return;
        }
        for (let index = 0; index < text.length; index++) {
            const code = text.charCodeAt(index);
            if (legadoIsActuallyWhitespace(code)) {
                if (!accumulator.lastCharIsSpace) {
                    accumulator.value += ' ';
                    accumulator.lastCharIsSpace = true;
                }
                continue;
            }
            if (code === 8203 || code === 173) continue;
            accumulator.value += text.charAt(index);
            accumulator.lastCharIsSpace = false;
        }
    }

    function legadoTrimJavaWhitespace(value) {
        const text = String(value || '');
        let start = 0;
        let end = text.length;
        while (start < end && text.charCodeAt(start) <= 32) start++;
        while (end > start && text.charCodeAt(end - 1) <= 32) end--;
        return text.substring(start, end);
    }

    function legadoAppendJsoupSpaceBoundary(accumulator) {
        if (accumulator.value.length > 0 && !accumulator.lastCharIsSpace) {
            accumulator.value += ' ';
        }
        accumulator.lastCharIsSpace = accumulator.value.length > 0 &&
            accumulator.value.charAt(accumulator.value.length - 1) === ' ';
    }

    function legadoIsBlockTag(tagName) {
        const normalized = String(tagName || '').toLowerCase();
        const blocks = [
            'html', 'head', 'body', 'frameset', 'script', 'noscript', 'style', 'meta',
            'link', 'title', 'frame', 'noframes', 'section', 'nav', 'aside', 'hgroup',
            'header', 'footer', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol',
            'pre', 'div', 'blockquote', 'hr', 'address', 'figure', 'figcaption', 'form',
            'fieldset', 'ins', 'del', 'dl', 'dt', 'dd', 'li', 'table', 'caption', 'thead',
            'tfoot', 'tbody', 'colgroup', 'col', 'tr', 'th', 'td', 'video', 'audio',
            'canvas', 'details', 'menu', 'plaintext', 'template', 'article', 'main',
            'svg', 'math', 'center', 'dir', 'applet', 'marquee', 'listing'
        ];
        return blocks.indexOf(normalized) >= 0;
    }

    function legadoIsFormatAsBlockTag(tagName) {
        const normalized = String(tagName || '').toLowerCase();
        const inline = [
            'object', 'base', 'font', 'tt', 'i', 'b', 'u', 'big', 'small', 'em',
            'strong', 'dfn', 'code', 'samp', 'kbd', 'var', 'cite', 'abbr', 'time',
            'acronym', 'mark', 'ruby', 'rt', 'rp', 'rtc', 'a', 'img', 'br', 'wbr',
            'map', 'q', 'sub', 'sup', 'bdo', 'iframe', 'embed', 'span', 'input',
            'select', 'textarea', 'label', 'button', 'optgroup', 'option', 'legend',
            'datalist', 'keygen', 'output', 'progress', 'meter', 'area', 'param',
            'source', 'track', 'summary', 'command', 'device', 'basefont', 'bgsound',
            'menuitem', 'data', 'bdi', 'strike', 'nobr', 'rb', 'text', 'mi', 'mo',
            'msup', 'mn', 'mtext', 'title', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
            'pre', 'address', 'li', 'th', 'td', 'script', 'style', 'ins', 'del', 's'
        ];
        return inline.indexOf(normalized) < 0;
    }

    function legadoIsPreserveWhitespaceTag(tagName) {
        const normalized = String(tagName || '').toLowerCase();
        return normalized === 'pre' || normalized === 'plaintext' ||
            normalized === 'title' || normalized === 'textarea';
    }

    function legadoIsPreserveWhitespaceNode(node) {
        let current = node;
        let depth = 0;
        while (current && depth < 6) {
            if (current.nodeType === 1) {
                const name = String(current.localName || current.tagName || '').toLowerCase();
                if (legadoIsPreserveWhitespaceTag(name)) return true;
            }
            current = current.parentNode;
            depth++;
        }
        return false;
    }

    function legadoAppendElementText(node, accumulator) {
        if (!node || !node.childNodes) return;
        for (let index = 0; index < node.childNodes.length; index++) {
            const child = node.childNodes[index];
            if (!child) continue;
            if (child.nodeType === 3) {
                legadoAppendText(accumulator, child.nodeValue || child.textContent || '',
                    legadoIsPreserveWhitespaceNode(child.parentNode));
                continue;
            }
            if (child.nodeType !== 1) continue;
            const tagName = String(child.localName || child.tagName || '').toLowerCase();
            if (tagName === 'br') {
                legadoAppendJsoupSpaceBoundary(accumulator);
                continue;
            }
            const isBlock = legadoIsBlockTag(tagName);
            if (isBlock && accumulator.value.length > 0 && !accumulator.lastCharIsSpace) {
                legadoAppendJsoupSpaceBoundary(accumulator);
            }
            const isDataTag = tagName === 'script' || tagName === 'style';
            if (!isDataTag) legadoAppendElementText(child, accumulator);
            const nextSibling = child.nextSibling;
            const nextIsInline = nextSibling && nextSibling.nodeType === 1 &&
                !legadoIsFormatAsBlockTag(nextSibling.localName || nextSibling.tagName);
            if (isBlock && nextSibling && (nextSibling.nodeType === 3 || nextIsInline)) {
                legadoAppendJsoupSpaceBoundary(accumulator);
            }
        }
    }

    function legadoElementText(node) {
        const nodeTagName = String(node && (node.localName || node.tagName) || '').toLowerCase();
        if (nodeTagName === 'script' || nodeTagName === 'style') return '';
        const accumulator = legadoCreateTextAccumulator();
        legadoAppendElementText(node, accumulator);
        return legadoTrimJavaWhitespace(accumulator.value);
    }

    function legadoElementOwnText(node) {
        if (!node || !node.childNodes) return '';
        const nodeTagName = String(node.localName || node.tagName || '').toLowerCase();
        if (nodeTagName === 'script' || nodeTagName === 'style') return '';
        const accumulator = legadoCreateTextAccumulator();
        for (let index = 0; index < node.childNodes.length; index++) {
            const child = node.childNodes[index];
            if (!child) continue;
            if (child.nodeType === 3) {
                legadoAppendText(accumulator, child.nodeValue || child.textContent || '',
                    legadoIsPreserveWhitespaceNode(child.parentNode));
            } else if (child.nodeType === 1 &&
                String(child.localName || child.tagName || '').toLowerCase() === 'br') {
                legadoAppendJsoupSpaceBoundary(accumulator);
            }
        }
        return legadoTrimJavaWhitespace(accumulator.value);
    }

    function legadoDirectTextNodeValues(node) {
        const values = [];
        if (!node || !node.childNodes) return values;
        const nodeTagName = String(node.localName || node.tagName || '').toLowerCase();
        if (nodeTagName === 'script' || nodeTagName === 'style') return values;
        for (let index = 0; index < node.childNodes.length; index++) {
            const child = node.childNodes[index];
            if (!child || (child.nodeType !== 3 && child.nodeType !== 4)) continue;
            values.push(String(child.nodeValue || child.textContent || ''));
        }
        return values;
    }

    function legadoNormalizeTextNode(value) {
        const accumulator = legadoCreateTextAccumulator();
        legadoAppendText(accumulator, value, false);
        return accumulator.value;
    }

    function legadoTextNodeList(node) {
        const rawValues = legadoDirectTextNodeValues(node);
        const list = [];
        for (let index = 0; index < rawValues.length; index++) {
            const wholeText = rawValues[index];
            const normalizedText = legadoNormalizeTextNode(wholeText);
            list.push({
                text: function() { return normalizedText; },
                getWholeText: function() { return wholeText; },
                toString: function() { return wholeText; }
            });
        }
        list.size = function() { return list.length; };
        list.get = function(index) { return list[Number(index) || 0] || null; };
        list.first = function() { return list.length > 0 ? list[0] : null; };
        list.last = function() { return list.length > 0 ? list[list.length - 1] : null; };
        list.isEmpty = function() { return list.length === 0; };
        list.toArray = function() { return list.slice(0); };
        return list;
    }

    // Parserless Rhino environments still need a structured projection. A
    // tag-stripping regex cannot distinguish direct text, descendants, or
    // Jsoup block boundaries, so build the small tree required by these APIs.
    function legadoDecodeFallbackEntities(value) {
        if (typeof global.__legadoDecodeHtmlEntities !== 'function') {
            throw new Error('Pinned Jsoup entity decoder is unavailable');
        }
        return global.__legadoDecodeHtmlEntities(value, false);
    }

    function legadoFallbackIsTagNameCharacter(character) {
        return /[A-Za-z0-9:_-]/.test(character);
    }

    function legadoFallbackIsVoidTag(tagName) {
        return [
            'area', 'base', 'basefont', 'bgsound', 'br', 'col', 'command', 'device',
            'embed', 'frame', 'hr', 'img', 'input', 'keygen', 'link', 'menuitem',
            'meta', 'param', 'source', 'track', 'wbr'
        ].indexOf(tagName) >= 0;
    }

    function legadoFallbackTokenize(value) {
        const html = String(value || '');
        const lower = html.toLowerCase();
        const tokens = [];
        let cursor = 0;
        let rawTag = '';
        while (cursor < html.length) {
            if (rawTag) {
                const closeStart = lower.indexOf('</' + rawTag, cursor);
                if (closeStart < 0) break;
                const boundary = html.charAt(closeStart + rawTag.length + 2);
                if (boundary && !/[\s>]/.test(boundary)) {
                    cursor = closeStart + rawTag.length + 2;
                    continue;
                }
                const closeEnd = html.indexOf('>', closeStart + 2);
                if (closeEnd < 0) break;
                tokens.push({ kind: 'close', name: rawTag, selfClosing: false });
                cursor = closeEnd + 1;
                rawTag = '';
                continue;
            }

            const tagStart = html.indexOf('<', cursor);
            if (tagStart < 0) {
                if (cursor < html.length) tokens.push({ kind: 'text', value: html.substring(cursor) });
                break;
            }
            if (tagStart > cursor) {
                tokens.push({ kind: 'text', value: html.substring(cursor, tagStart) });
            }
            if (html.substring(tagStart, tagStart + 4) === '<!--') {
                const commentEnd = html.indexOf('-->', tagStart + 4);
                tokens.push({ kind: 'comment' });
                cursor = commentEnd < 0 ? html.length : commentEnd + 3;
                continue;
            }

            let scan = tagStart + 1;
            let quote = '';
            while (scan < html.length) {
                const character = html.charAt(scan);
                if (quote) {
                    if (character === quote) quote = '';
                } else if (character === '"' || character === "'") {
                    quote = character;
                } else if (character === '>') {
                    break;
                }
                scan++;
            }
            if (scan >= html.length) {
                tokens.push({ kind: 'text', value: html.substring(tagStart) });
                break;
            }

            const body = html.substring(tagStart + 1, scan);
            let bodyCursor = 0;
            while (bodyCursor < body.length && body.charCodeAt(bodyCursor) <= 32) bodyCursor++;
            if (body.charAt(bodyCursor) === '!' || body.charAt(bodyCursor) === '?') {
                tokens.push({ kind: 'comment' });
                cursor = scan + 1;
                continue;
            }
            const closing = body.charAt(bodyCursor) === '/';
            if (closing) bodyCursor++;
            while (bodyCursor < body.length && body.charCodeAt(bodyCursor) <= 32) bodyCursor++;
            const nameStart = bodyCursor;
            while (bodyCursor < body.length &&
                legadoFallbackIsTagNameCharacter(body.charAt(bodyCursor))) {
                bodyCursor++;
            }
            const name = body.substring(nameStart, bodyCursor).toLowerCase();
            if (!name) {
                tokens.push({ kind: 'text', value: html.substring(tagStart, scan + 1) });
                cursor = scan + 1;
                continue;
            }
            let tail = body.length - 1;
            while (tail >= 0 && body.charCodeAt(tail) <= 32) tail--;
            const selfClosing = !closing &&
                (body.charAt(tail) === '/' || legadoFallbackIsVoidTag(name));
            tokens.push({
                kind: closing ? 'close' : 'open',
                name: name,
                selfClosing: selfClosing
            });
            cursor = scan + 1;
            if (!closing && !selfClosing && (name === 'script' || name === 'style')) {
                rawTag = name;
            } else if (!closing && !selfClosing && name === 'plaintext') {
                if (cursor < html.length) tokens.push({ kind: 'text', value: html.substring(cursor) });
                cursor = html.length;
            }
        }
        return tokens;
    }

    function legadoFallbackElement(name) {
        return { kind: 'element', name: name, children: [], parent: null };
    }

    function legadoFallbackBuildTree(value, expectedTagName) {
        const syntheticRoot = legadoFallbackElement(String(expectedTagName || '').toLowerCase());
        const stack = [syntheticRoot];
        const tokens = legadoFallbackTokenize(value);
        for (let index = 0; index < tokens.length; index++) {
            const token = tokens[index];
            const parent = stack[stack.length - 1];
            if (token.kind === 'text') {
                if (token.value) {
                    parent.children.push({
                        kind: 'text',
                        value: legadoDecodeFallbackEntities(token.value),
                        parent: parent
                    });
                }
                continue;
            }
            if (token.kind === 'comment') {
                parent.children.push({ kind: 'comment', parent: parent });
                continue;
            }
            if (token.kind === 'open') {
                const element = legadoFallbackElement(token.name);
                element.parent = parent;
                parent.children.push(element);
                if (!token.selfClosing) stack.push(element);
                continue;
            }
            for (let stackIndex = stack.length - 1; stackIndex > 0; stackIndex--) {
                if (stack[stackIndex].name === token.name) {
                    stack.length = stackIndex;
                    break;
                }
            }
        }

        const expected = String(expectedTagName || '').toLowerCase();
        if (expected) {
            for (let index = 0; index < syntheticRoot.children.length; index++) {
                const child = syntheticRoot.children[index];
                if (child.kind === 'text' && legadoTrimJavaWhitespace(child.value) === '') continue;
                if (child.kind === 'element' && child.name === expected) return child;
                break;
            }
        }
        return syntheticRoot;
    }

    function legadoFallbackPreservesWhitespace(node) {
        let current = node;
        let depth = 0;
        while (current && depth < 6) {
            if (current.kind === 'element' && legadoIsPreserveWhitespaceTag(current.name)) {
                return true;
            }
            current = current.parent;
            depth++;
        }
        return false;
    }

    function legadoFallbackAppendChildren(node, accumulator) {
        if (!node || !node.children) return;
        for (let index = 0; index < node.children.length; index++) {
            const child = node.children[index];
            if (child.kind === 'text') {
                legadoAppendText(accumulator, child.value, legadoFallbackPreservesWhitespace(child.parent));
                continue;
            }
            if (child.kind !== 'element') continue;
            if (child.name === 'br') {
                legadoAppendJsoupSpaceBoundary(accumulator);
                continue;
            }
            const isBlock = legadoIsBlockTag(child.name);
            if (isBlock && accumulator.value.length > 0 && !accumulator.lastCharIsSpace) {
                legadoAppendJsoupSpaceBoundary(accumulator);
            }
            if (child.name !== 'script' && child.name !== 'style') {
                legadoFallbackAppendChildren(child, accumulator);
            }
            const next = node.children[index + 1];
            const nextIsInline = next && (next.kind !== 'element' ||
                !legadoIsFormatAsBlockTag(next.name));
            if (isBlock && next && nextIsInline) {
                legadoAppendJsoupSpaceBoundary(accumulator);
            }
        }
    }

    function legadoFallbackText(node) {
        if (!node || node.name === 'script' || node.name === 'style') return '';
        const accumulator = legadoCreateTextAccumulator();
        legadoFallbackAppendChildren(node, accumulator);
        return legadoTrimJavaWhitespace(accumulator.value);
    }

    function legadoFallbackOwnText(node) {
        if (!node || node.name === 'script' || node.name === 'style') return '';
        const accumulator = legadoCreateTextAccumulator();
        for (let index = 0; index < node.children.length; index++) {
            const child = node.children[index];
            if (child.kind === 'text') {
                legadoAppendText(accumulator, child.value, legadoFallbackPreservesWhitespace(child.parent));
            } else if (child.kind === 'element' && child.name === 'br') {
                legadoAppendJsoupSpaceBoundary(accumulator);
            }
        }
        return legadoTrimJavaWhitespace(accumulator.value);
    }

    function legadoFallbackTextNodeList(node) {
        const list = [];
        if (!node || node.name === 'script' || node.name === 'style') return list;
        for (let index = 0; index < node.children.length; index++) {
            const child = node.children[index];
            if (child.kind !== 'text') continue;
            const wholeText = child.value;
            const normalizedText = legadoNormalizeTextNode(wholeText);
            list.push({
                text: function() { return normalizedText; },
                getWholeText: function() { return wholeText; },
                toString: function() { return wholeText; }
            });
        }
        list.size = function() { return list.length; };
        list.get = function(index) { return list[Number(index) || 0] || null; };
        list.first = function() { return list.length > 0 ? list[0] : null; };
        list.last = function() { return list.length > 0 ? list[list.length - 1] : null; };
        list.isEmpty = function() { return list.length === 0; };
        list.toArray = function() { return list.slice(0); };
        return list;
    }

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
            if (attrName === 'text') {
                return this.text();
            }
            if (attrName === 'ownText') {
                return this.ownText();
            }
            if (attrName === 'textNodes') {
                const nodes = this.textNodes();
                const values = [];
                for (let index = 0; index < nodes.length; index++) {
                    const value = legadoTrimJavaWhitespace(nodes[index].text());
                    if (value) values.push(value);
                }
                return values.join('\n');
            }
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
                return legadoElementText(this._el);
            }
            const tree = legadoFallbackBuildTree(this._html, this._tagName);
            return legadoFallbackText(tree);
        }

        /**
         * 获取自身文本（不含子元素）
         */
        ownText() {
            if (this._el) {
                return legadoElementOwnText(this._el);
            }
            const tree = legadoFallbackBuildTree(this._html, this._tagName);
            return legadoFallbackOwnText(tree);
        }

        textNodes() {
            if (this._el) return legadoTextNodeList(this._el);
            const tree = legadoFallbackBuildTree(this._html, this._tagName);
            return legadoFallbackTextNodeList(tree);
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

        textNodes() {
            const nodes = [];
            this._elements.forEach(el => {
                const textNodes = el.textNodes();
                for (let index = 0; index < textNodes.length; index++) {
                    nodes.push(textNodes[index]);
                }
            });
            return nodes;
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

})(window);
