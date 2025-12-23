/**
 * HTML 元素节点类
 * 表示 HTML 中的元素，如 <div>, <span>, <a> 等
 * 
 * 基于 node-html-parser 设计，提供完整的 DOM 操作和 CSS 选择器查询能力
 */

import { NodeType } from './NodeType';
import { Node } from './Node';
import { TextNode } from './TextNode';
import { CommentNode } from './CommentNode';
import { Matcher, SelectorNode, SelectorPart, Combinator, AttributeSelector, PseudoClass } from './Matcher';
import { HtmlParserLogger } from './HtmlParserLogger';

/**
 * 属性映射类
 */
export class Attributes {
  private _map: Map<string, string> = new Map();

  set(key: string, value: string): void {
    this._map.set(key.toLowerCase(), value);
  }

  get(key: string): string | undefined {
    return this._map.get(key.toLowerCase());
  }

  has(key: string): boolean {
    return this._map.has(key.toLowerCase());
  }

  remove(key: string): boolean {
    return this._map.delete(key.toLowerCase());
  }

  keys(): string[] {
    const result: string[] = [];
    this._map.forEach((_value: string, key: string) => {
      result.push(key);
    });
    return result;
  }

  entries(): Array<[string, string]> {
    const result: Array<[string, string]> = [];
    this._map.forEach((value: string, key: string) => {
      result.push([key, value]);
    });
    return result;
  }

  clone(): Attributes {
    const newAttrs = new Attributes();
    this._map.forEach((value: string, key: string) => {
      newAttrs.set(key, value);
    });
    return newAttrs;
  }
}

/**
 * HTML 元素类
 */
export class HTMLElement extends Node {
  tagName: string;
  rawTagName: string;
  private _attrs: Attributes = new Attributes();
  rawAttrs: string = '';
  private _voidTag: boolean = false;

  constructor(
    tagName: string,
    attrs: Attributes | null = null,
    rawAttrs: string = '',
    parentNode: Node | null = null,
    range?: [number, number],
    voidTag: boolean = false
  ) {
    super(NodeType.ELEMENT_NODE, parentNode, range);
    this.rawTagName = tagName;
    this.tagName = tagName.toLowerCase();
    if (attrs) {
      this._attrs = attrs;
    }
    this.rawAttrs = rawAttrs;
    this._voidTag = voidTag;
  }

  /**
   * 获取所有属性
   */
  get attributes(): Attributes {
    return this._attrs.clone();
  }

  /**
   * 获取属性值
   */
  getAttribute(name: string): string | undefined {
    return this._attrs.get(name);
  }

  /**
   * 设置属性值
   */
  setAttribute(name: string, value: string): HTMLElement {
    this._attrs.set(name, value);
    return this;
  }

  /**
   * 移除属性
   */
  removeAttribute(name: string): HTMLElement {
    this._attrs.remove(name);
    return this;
  }

  /**
   * 检查是否有属性
   */
  hasAttribute(name: string): boolean {
    return this._attrs.has(name);
  }

  /**
   * 获取 id 属性
   */
  get id(): string {
    return this._attrs.get('id') || '';
  }

  /**
   * 设置 id 属性
   */
  set id(value: string) {
    this._attrs.set('id', value);
  }

  /**
   * 获取 class 列表
   */
  get classList(): string[] {
    const classAttr = this._attrs.get('class') || '';
    return classAttr.split(/\s+/).filter((c: string): boolean => c.length > 0);
  }

  /**
   * 获取 className
   */
  get className(): string {
    return this._attrs.get('class') || '';
  }

  /**
   * 设置 className
   */
  set className(value: string) {
    this._attrs.set('class', value);
  }

  /**
   * 获取原始文本内容
   */
  get rawText(): string {
    let text = '';
    for (const child of this.childNodes) {
      if (child.nodeType === NodeType.TEXT_NODE) {
        text += (child as TextNode).rawText;
      } else if (child.nodeType === NodeType.ELEMENT_NODE) {
        text += (child as HTMLElement).rawText;
      }
    }
    return text;
  }

  /**
   * 获取纯文本内容
   */
  get text(): string {
    return this.textContent.trim();
  }

  /**
   * 获取 innerHTML
   */
  get innerHTML(): string {
    let html = '';
    for (const child of this.childNodes) {
      if (child.nodeType === NodeType.TEXT_NODE) {
        html += (child as TextNode).rawText;
      } else if (child.nodeType === NodeType.ELEMENT_NODE) {
        html += (child as HTMLElement).outerHTML;
      } else if (child.nodeType === NodeType.COMMENT_NODE) {
        html += (child as CommentNode).toString();
      }
    }
    return html;
  }

  /**
   * 获取 outerHTML
   */
  get outerHTML(): string {
    let attrs = '';
    for (const entry of this._attrs.entries()) {
      const key = entry[0];
      const value = entry[1];
      attrs += ` ${key}="${this.escapeAttrValue(value)}"`;
    }
    
    const voidTags = ['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 
                      'link', 'meta', 'param', 'source', 'track', 'wbr'];
    
    if (this._voidTag || voidTags.includes(this.tagName)) {
      return `<${this.tagName}${attrs}>`;
    }
    
    return `<${this.tagName}${attrs}>${this.innerHTML}</${this.tagName}>`;
  }

  /**
   * 转义属性值
   */
  private escapeAttrValue(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  /**
   * 获取子元素列表
   */
  get children(): HTMLElement[] {
    return this.childNodes.filter((n: Node): boolean => n.nodeType === NodeType.ELEMENT_NODE) as HTMLElement[];
  }

  /**
   * 获取第一个子元素
   */
  get firstChild(): Node | null {
    return this.childNodes.length > 0 ? this.childNodes[0] : null;
  }

  /**
   * 获取最后一个子元素
   */
  get lastChild(): Node | null {
    return this.childNodes.length > 0 ? this.childNodes[this.childNodes.length - 1] : null;
  }

  /**
   * 添加子节点
   */
  appendChild(node: Node): HTMLElement {
    node.parentNode = this;
    this.childNodes.push(node);
    return this;
  }

  /**
   * 移除子节点
   */
  removeChild(node: Node): HTMLElement {
    const index = this.childNodes.indexOf(node);
    if (index >= 0) {
      this.childNodes.splice(index, 1);
      node.parentNode = null;
    }
    return this;
  }

  /**
   * 克隆节点
   */
  clone(deep: boolean = false): HTMLElement {
    const newRange: [number, number] = [this.range[0], this.range[1]];
    const cloned = new HTMLElement(
      this.rawTagName,
      this._attrs.clone(),
      this.rawAttrs,
      null,
      newRange,
      this._voidTag
    );
    
    if (deep) {
      for (const child of this.childNodes) {
        if (child.nodeType === NodeType.TEXT_NODE) {
          cloned.appendChild((child as TextNode).clone());
        } else if (child.nodeType === NodeType.ELEMENT_NODE) {
          cloned.appendChild((child as HTMLElement).clone(true));
        } else if (child.nodeType === NodeType.COMMENT_NODE) {
          cloned.appendChild((child as CommentNode).clone());
        }
      }
    }
    
    return cloned;
  }

  // ==================== CSS 选择器查询 ====================

  /**
   * 使用 CSS 选择器查询单个元素
   */
  querySelector(selector: string): HTMLElement | null {
    const results = this.querySelectorAll(selector);
    return results.length > 0 ? results[0] : null;
  }

  /**
   * 使用 CSS 选择器查询所有匹配元素
   */
  querySelectorAll(selector: string): HTMLElement[] {
    const selectorGroups = Matcher.parseSelector(selector);
    if (selectorGroups.length === 0) {
      HtmlParserLogger.warn(`无效的选择器: "${selector}"`);
      return [];
    }
    const results: HTMLElement[] = [];
    const seen = new Set<HTMLElement>();
    
    for (const chain of selectorGroups) {
      const matches = this.matchSelectorChain(chain, 0);
      for (const match of matches) {
        if (!seen.has(match)) {
          seen.add(match);
          results.push(match);
        }
      }
    }
    
    return results;
  }

  /**
   * 匹配选择器链
   */
  private matchSelectorChain(chain: SelectorNode[], startIndex: number): HTMLElement[] {
    if (startIndex >= chain.length) return [];
    
    const currentNode = chain[startIndex];
    const isLast = startIndex === chain.length - 1;
    
    const descendants = this.getElementsByTagName('*');
    const matches: HTMLElement[] = [];
    
    for (const elem of descendants) {
      if (this.matchesSelectorPart(elem, currentNode.part)) {
        if (isLast) {
          matches.push(elem);
        } else {
          const combinator = currentNode.combinator;
          const nextMatches = this.matchNextInChain(elem, chain, startIndex + 1, combinator);
          for (const m of nextMatches) {
            matches.push(m);
          }
        }
      }
    }
    
    return matches;
  }

  /**
   * 匹配链中的下一个节点
   */
  private matchNextInChain(
    currentElem: HTMLElement, 
    chain: SelectorNode[], 
    nextIndex: number,
    combinator: Combinator | null
  ): HTMLElement[] {
    if (nextIndex >= chain.length) return [];
    
    const nextNode = chain[nextIndex];
    const isLast = nextIndex === chain.length - 1;
    const results: HTMLElement[] = [];
    
    let candidates: HTMLElement[] = [];
    
    if (combinator === Combinator.CHILD) {
      candidates = currentElem.children;
    } else if (combinator === Combinator.ADJACENT_SIBLING) {
      const nextSibling = currentElem.nextElementSibling;
      if (nextSibling) {
        candidates = [nextSibling];
      }
    } else if (combinator === Combinator.GENERAL_SIBLING) {
      candidates = this.getFollowingSiblings(currentElem);
    } else {
      candidates = currentElem.getElementsByTagName('*');
    }
    
    for (const candidate of candidates) {
      if (this.matchesSelectorPart(candidate, nextNode.part)) {
        if (isLast) {
          results.push(candidate);
        } else {
          const nextCombinator = nextNode.combinator;
          const nextMatches = this.matchNextInChain(candidate, chain, nextIndex + 1, nextCombinator);
          for (const m of nextMatches) {
            results.push(m);
          }
        }
      }
    }
    
    return results;
  }

  /**
   * 获取后续兄弟元素
   */
  private getFollowingSiblings(elem: HTMLElement): HTMLElement[] {
    if (!elem.parentNode) return [];
    const parent = elem.parentNode as HTMLElement;
    const siblings = parent.children;
    const index = siblings.indexOf(elem);
    return index >= 0 ? siblings.slice(index + 1) : [];
  }

  /**
   * 检查元素是否匹配选择器部分
   */
  private matchesSelectorPart(elem: HTMLElement, part: SelectorPart): boolean {
    if (part.tagName && part.tagName !== '*' && elem.tagName !== part.tagName) {
      return false;
    }
    
    if (part.id && elem.id !== part.id) {
      return false;
    }
    
    for (const className of part.classes) {
      if (!elem.classList.includes(className)) {
        return false;
      }
    }
    
    for (const attrSelector of part.attributes) {
      const attrValue = elem.getAttribute(attrSelector.name);
      if (!Matcher.matchAttribute(attrValue, attrSelector)) {
        return false;
      }
    }
    
    for (const pseudo of part.pseudoClasses) {
      if (!this.matchesPseudoClass(elem, pseudo)) {
        return false;
      }
    }
    
    return true;
  }

  /**
   * 检查元素是否匹配伪类
   */
  private matchesPseudoClass(elem: HTMLElement, pseudo: PseudoClass): boolean {
    const parent = elem.parentNode as HTMLElement | null;
    
    if (pseudo.name === 'first-child') {
      if (!parent) return false;
      return parent.children[0] === elem;
    } else if (pseudo.name === 'last-child') {
      if (!parent) return false;
      const children = parent.children;
      return children[children.length - 1] === elem;
    } else if (pseudo.name === 'nth-child') {
      if (!parent) return false;
      return this.matchNthChild(elem, parent, pseudo.argument);
    } else if (pseudo.name === 'only-child') {
      if (!parent) return false;
      return parent.children.length === 1;
    } else if (pseudo.name === 'empty') {
      return elem.childNodes.length === 0;
    } else if (pseudo.name === 'contains') {
      return elem.text.includes(pseudo.argument);
    }
    
    return true;
  }

  /**
   * 匹配 :nth-child
   */
  private matchNthChild(elem: HTMLElement, parent: HTMLElement, argument: string): boolean {
    const index = parent.children.indexOf(elem) + 1;
    return this.matchNthExpression(index, argument);
  }

  /**
   * 匹配 nth 表达式
   */
  private matchNthExpression(index: number, expression: string): boolean {
    const expr = expression.trim().toLowerCase();
    
    if (expr === 'odd') {
      return index % 2 === 1;
    }
    if (expr === 'even') {
      return index % 2 === 0;
    }
    
    const numMatch = expr.match(/^(\d+)$/);
    if (numMatch) {
      return index === parseInt(numMatch[1], 10);
    }
    
    return true;
  }

  // ==================== 便捷查询方法 ====================

  /**
   * 通过 ID 获取元素
   */
  getElementById(id: string): HTMLElement | null {
    return this.querySelector(`#${id}`);
  }

  /**
   * 通过类名获取元素列表
   */
  getElementsByClassName(className: string): HTMLElement[] {
    return this.querySelectorAll(`.${className}`);
  }

  /**
   * 通过标签名获取元素列表
   */
  getElementsByTagName(tagName: string): HTMLElement[] {
    const results: HTMLElement[] = [];
    const lowerTagName = tagName.toLowerCase();
    const matchAll = lowerTagName === '*';
    
    const traverse = (node: Node): void => {
      for (const child of node.childNodes) {
        if (child.nodeType === NodeType.ELEMENT_NODE) {
          const elem = child as HTMLElement;
          if (matchAll || elem.tagName === lowerTagName) {
            results.push(elem);
          }
          traverse(elem);
        }
      }
    };
    
    traverse(this);
    return results;
  }

  /**
   * 检查元素是否匹配选择器
   */
  matches(selector: string): boolean {
    const selectorGroups = Matcher.parseSelector(selector);
    
    for (const chain of selectorGroups) {
      if (chain.length === 1 && this.matchesSelectorPart(this, chain[0].part)) {
        return true;
      }
    }
    
    return false;
  }

  /**
   * 获取下一个元素兄弟
   */
  get nextElementSibling(): HTMLElement | null {
    if (!this.parentNode) return null;
    const parent = this.parentNode as HTMLElement;
    const siblings = parent.children;
    const index = siblings.indexOf(this);
    return index >= 0 && index < siblings.length - 1 ? siblings[index + 1] : null;
  }

  /**
   * 获取上一个元素兄弟
   */
  get previousElementSibling(): HTMLElement | null {
    if (!this.parentNode) return null;
    const parent = this.parentNode as HTMLElement;
    const siblings = parent.children;
    const index = siblings.indexOf(this);
    return index > 0 ? siblings[index - 1] : null;
  }

  /**
   * 转换为字符串
   */
  toString(): string {
    return this.outerHTML;
  }
}
