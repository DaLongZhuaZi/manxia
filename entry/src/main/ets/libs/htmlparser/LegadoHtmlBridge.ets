/**
 * Legado HTML 解析桥接层
 * 将 HTML 解析器与 Legado 规则解析器集成
 * 
 * 提供与 Legado 规则语法兼容的 HTML 解析功能
 * 支持 class.xxx, id.xxx, tag.xxx 等 Legado 特有语法
 */

import { parse, HTMLElement } from './index';
import { HtmlParserLogger } from './HtmlParserLogger';

/**
 * 索引解析结果
 */
class IndexResult {
  selector: string = '';
  hasIndex: boolean = false;
  exclude: boolean = false;
  indexes: number[] = [];
  start: number = 0;
  end: number = -1;
}

/**
 * Legado HTML 解析桥接类
 */
export class LegadoHtmlBridge {
  private root: HTMLElement | null = null;
  private content: string = '';

  /**
   * 设置要解析的 HTML 内容
   */
  setContent(html: string): LegadoHtmlBridge {
    this.content = html;
    try {
      this.root = parse(html);
      HtmlParserLogger.debug(`HTML 解析完成，内容长度: ${html.length}`);
    } catch (e) {
      HtmlParserLogger.error(`HTML 解析失败: ${String(e)}`);
      this.root = null;
    }
    return this;
  }

  /**
   * 获取解析后的根元素
   */
  getRoot(): HTMLElement | null {
    return this.root;
  }

  /**
   * 获取原始内容
   */
  getContent(): string {
    return this.content;
  }

  /**
   * 使用 CSS 选择器查询单个元素
   */
  querySelector(selector: string): HTMLElement | null {
    if (!this.root) return null;
    const elements = this.root.select(selector);
    return elements.length > 0 ? elements[0] : null;
  }

  /**
   * 使用 CSS 选择器查询所有元素
   */
  querySelectorAll(selector: string): HTMLElement[] {
    if (!this.root) return [];
    return this.root.select(selector);
  }

  /**
   * 使用 Legado 规则语法查询元素
   * 支持: class.xxx, id.xxx, tag.xxx, text.xxx
   */
  findByLegadoRule(rule: string): HTMLElement[] {
    if (!this.root) return [];

    if (rule.startsWith('class.')) {
      const className = rule.substring(6);
      return this.root.select(`.${className}`);
    } else if (rule.startsWith('id.')) {
      const idName = rule.substring(3);
      const elem = this.root.select(`#${idName}`)[0];
      return elem ? [elem] : [];
    } else if (rule.startsWith('tag.')) {
      const tagName = rule.substring(4);
      return this.root.select(tagName);
    } else if (rule.startsWith('text.')) {
      const searchText = rule.substring(5);
      return this.findByText(searchText);
    } else {
      return this.root.getElementsByTagName(rule);
    }
  }

  /**
   * 按文本内容查找元素
   */
  private findByText(searchText: string): HTMLElement[] {
    if (!this.root) return [];
    return this.findByTextInContext(this.root, searchText);
  }

  /**
   * 解析 Legado 链式规则
   * 格式: class.xxx@tag.a.0@text
   */
  parseChainRule(rule: string): string {
    if (!this.root) return '';

    const rules = this.splitByAt(rule);
    if (rules.length === 0) return '';

    let elements: HTMLElement[] = [this.root];
    const lastIndex = rules.length - 1;

    for (let i = 0; i < lastIndex; i++) {
      const newElements: HTMLElement[] = [];
      for (const elem of elements) {
        const found = this.findElementsInContext(elem, rules[i]);
        for (const f of found) {
          newElements.push(f);
        }
      }
      elements = newElements;
      if (elements.length === 0) return '';
    }

    const lastRule = rules[lastIndex];
    return this.getResultByLastRule(elements, lastRule);
  }

  /**
   * 解析 Legado 链式规则，返回元素列表
   */
  parseChainRuleToElements(rule: string): HTMLElement[] {
    if (!this.root) return [];

    const rules = this.splitByAt(rule);
    if (rules.length === 0) return [];

    let elements: HTMLElement[] = [this.root];

    for (const r of rules) {
      const newElements: HTMLElement[] = [];
      for (const elem of elements) {
        const found = this.findElementsInContext(elem, r);
        for (const f of found) {
          newElements.push(f);
        }
      }
      elements = newElements;
      if (elements.length === 0) return [];
    }

    return elements;
  }

  /**
   * 解析链式规则，返回元素的 outerHTML 列表
   */
  parseChainRuleToHtmlList(rule: string): string[] {
    const elements = this.parseChainRuleToElements(rule);
    return elements.map((elem: HTMLElement): string => elem.outerHTML);
  }

  /**
   * 在指定元素上下文中查找元素
   */
  private findElementsInContext(context: HTMLElement, rule: string): HTMLElement[] {
    const indexResult = this.parseIndex(rule);
    const selector = indexResult.selector;

    let results: HTMLElement[] = [];

    if (selector === 'children' || selector === '') {
      results = context.children;
    } else if (selector.startsWith('class.')) {
      const className = selector.substring(6);
      results = context.select(`.${className}`);
    } else if (selector.startsWith('id.')) {
      const idName = selector.substring(3);
      const elem = context.select(`#${idName}`)[0];
      results = elem ? [elem] : [];
    } else if (selector.startsWith('tag.')) {
      const tagName = selector.substring(4);
      results = context.select(tagName);
    } else if (selector.startsWith('text.')) {
      const searchText = selector.substring(5);
      results = this.findByTextInContext(context, searchText);
    } else {
      results = context.select(selector);
    }

    if (indexResult.hasIndex) {
      results = this.applyIndex(results, indexResult);
    }

    return results;
  }

  /**
   * 在指定上下文中按文本查找
   */
  private findByTextInContext(context: HTMLElement, searchText: string): HTMLElement[] {
    const results: HTMLElement[] = [];
    // AnalyzeByJSoup maps text.xxx to Jsoup getElementsContainingOwnText.
    // Use the Jsoup-style selection entry so a normal context element is a
    // candidate, while the parser's synthetic Document root remains hidden.
    const allElements = context.select('*');
    
    for (const elem of allElements) {
      if (elem.ownText.includes(searchText)) {
        results.push(elem);
      }
    }
    
    return results;
  }

  /**
   * 根据最后一个规则获取结果
   */
  private getResultByLastRule(elements: HTMLElement[], lastRule: string): string {
    const attrNames = ['text', 'href', 'src', 'html', 'textnodes', 'owntext', 'all',
                       'title', 'alt', 'value', 'content', 'data-src', 'data-original',
                       'class', 'id', 'name', 'type', 'placeholder', 'action'];
    const lowerRule = lastRule.toLowerCase();

    if (attrNames.includes(lowerRule)) {
      const results: string[] = [];
      for (const elem of elements) {
        const text = this.extractAttribute(elem, lowerRule);
        if (text) {
          results.push(text);
        }
      }
      return results.join('\n');
    }

    const newElements: HTMLElement[] = [];
    for (const elem of elements) {
      const found = this.findElementsInContext(elem, lastRule);
      for (const f of found) {
        newElements.push(f);
      }
    }

    if (newElements.length === 0) return '';

    const results: string[] = [];
    for (const elem of newElements) {
      const text = elem.text;
      if (text) {
        results.push(text);
      }
    }
    return results.join('\n');
  }

  /**
   * 提取元素属性
   */
  extractAttribute(elem: HTMLElement, attr: string): string {
    const lowerAttr = attr.toLowerCase();

    switch (lowerAttr) {
      case 'text':
        return elem.text;
      case 'textnodes':
        return elem.textNodes;
      case 'owntext':
        return elem.ownText;
      case 'html':
        // AnalyzeByJSoup returns Elements.outerHtml() for @html after it has
        // removed script/style nodes. Returning innerHTML loses the selected
        // block wrapper, which is observable to HtmlFormatter as the missing
        // leading reader indent.
        return this.removeScriptAndStyleElements(elem.outerHTML);
      case 'all':
        return elem.outerHTML;
      case 'outerhtml':
        return elem.outerHTML;
      default:
        return elem.getAttribute(lowerAttr) || '';
    }
  }

  private removeScriptAndStyleElements(html: string): string {
    return html
      .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
      .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '');
  }

  /**
   * 使用 @ 分割规则链
   */
  private splitByAt(rule: string): string[] {
    const rules: string[] = [];
    let current = '';
    let inQuote = false;
    let quoteChar = '';
    let depth = 0;

    for (let i = 0; i < rule.length; i++) {
      const c = rule[i];

      if ((c === '"' || c === "'") && (i === 0 || rule[i - 1] !== '\\')) {
        if (!inQuote) {
          inQuote = true;
          quoteChar = c;
        } else if (c === quoteChar) {
          inQuote = false;
        }
      }

      if (!inQuote) {
        if (c === '[' || c === '(') {
          depth++;
        } else if (c === ']' || c === ')') {
          depth--;
        }
      }

      if (c === '@' && !inQuote && depth === 0) {
        if (current.trim()) {
          rules.push(current.trim());
        }
        current = '';
      } else {
        current += c;
      }
    }

    if (current.trim()) {
      rules.push(current.trim());
    }

    return rules;
  }

  /**
   * 解析索引
   */
  private parseIndex(rule: string): IndexResult {
    const result = new IndexResult();
    result.selector = rule;

    if (rule.endsWith(']')) {
      const bracketStart = rule.lastIndexOf('[');
      if (bracketStart !== -1) {
        result.selector = rule.substring(0, bracketStart);
        const indexStr = rule.substring(bracketStart + 1, rule.length - 1);
        result.hasIndex = true;

        if (indexStr.startsWith('!')) {
          result.exclude = true;
          this.parseIndexStr(indexStr.substring(1), result);
        } else {
          this.parseIndexStr(indexStr, result);
        }
        return result;
      }
    }

    const dotMatch = rule.match(/\.(-?\d+)$/);
    if (dotMatch) {
      result.selector = rule.substring(0, rule.length - dotMatch[0].length);
      result.hasIndex = true;
      result.indexes.push(parseInt(dotMatch[1]));
      return result;
    }

    const rangeMatch = rule.match(/\.(-?\d+):(-?\d+)$/);
    if (rangeMatch) {
      result.selector = rule.substring(0, rule.length - rangeMatch[0].length);
      result.hasIndex = true;
      result.start = parseInt(rangeMatch[1]);
      result.end = parseInt(rangeMatch[2]);
      return result;
    }

    return result;
  }

  /**
   * 解析索引字符串
   */
  private parseIndexStr(indexStr: string, result: IndexResult): void {
    if (indexStr.includes(':')) {
      const parts = indexStr.split(':');
      result.start = parts[0] ? parseInt(parts[0]) : 0;
      result.end = parts.length > 1 && parts[1] ? parseInt(parts[1]) : -1;
    } else {
      result.indexes.push(parseInt(indexStr));
    }
  }

  /**
   * 应用索引筛选
   */
  private applyIndex(elements: HTMLElement[], indexResult: IndexResult): HTMLElement[] {
    const len = elements.length;
    if (len === 0) return [];

    if (indexResult.indexes.length > 0) {
      const results: HTMLElement[] = [];
      for (const idx of indexResult.indexes) {
        const actualIdx = idx < 0 ? len + idx : idx;
        if (actualIdx >= 0 && actualIdx < len) {
          if (indexResult.exclude) {
            for (let i = 0; i < len; i++) {
              if (i !== actualIdx) {
                results.push(elements[i]);
              }
            }
          } else {
            results.push(elements[actualIdx]);
          }
        }
      }
      return results;
    }

    if (indexResult.start !== 0 || indexResult.end !== -1) {
      let start = indexResult.start < 0 ? len + indexResult.start : indexResult.start;
      let end = indexResult.end < 0 ? len + indexResult.end : indexResult.end;
      
      start = Math.max(0, Math.min(start, len - 1));
      end = Math.max(0, Math.min(end, len - 1));

      const results: HTMLElement[] = [];
      if (start <= end) {
        for (let i = start; i <= end; i++) {
          results.push(elements[i]);
        }
      }
      return results;
    }

    return elements;
  }
}

/**
 * 创建 Legado HTML 桥接实例
 */
export function createLegadoHtmlBridge(html?: string): LegadoHtmlBridge {
  const bridge = new LegadoHtmlBridge();
  if (html) {
    bridge.setContent(html);
  }
  return bridge;
}
