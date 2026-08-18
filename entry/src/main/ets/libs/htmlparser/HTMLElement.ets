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
import { LegadoTextAccumulator, LegadoTextNormalization } from './LegadoTextNormalization';

interface LegadoRegexPrefix {
  pattern: string;
  flags: string;
}

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
    const accumulator = new LegadoTextAccumulator();
    this.appendJsoupText(this, accumulator);
    return accumulator.toTrimmedString();
  }

  /**
   * Jsoup Element.textNodes() projects each direct TextNode independently:
   * TextNode.text() normalizes its own whitespace, Java trim is applied to
   * each item, and nonblank items are joined with LF.
   */
  get textNodes(): string {
    if (LegadoTextNormalization.isDataTag(this.tagName)) {
      return '';
    }
    const values: string[] = [];
    for (const child of this.childNodes) {
      if (child.nodeType !== NodeType.TEXT_NODE) {
        continue;
      }
      const textNode = child as TextNode;
      const accumulator = new LegadoTextAccumulator();
      accumulator.appendText(textNode.text, false);
      const value = accumulator.toTrimmedString();
      if (value.length > 0) {
        values.push(value);
      }
    }
    return values.join('\n');
  }

  /**
   * 获取当前元素的直接文本节点内容，不包含后代元素文本。
   * Jsoup 的 :matchesOwn/:containsOwn 依赖这一语义。
   */
  get ownText(): string {
    if (LegadoTextNormalization.isDataTag(this.tagName)) {
      return '';
    }
    const accumulator = new LegadoTextAccumulator();
    for (const child of this.childNodes) {
      if (child.nodeType === NodeType.TEXT_NODE) {
        const textNode = child as TextNode;
        accumulator.appendText(textNode.text, this.isPreserveWhitespace(textNode.parentNode));
      } else if (child.nodeType === NodeType.ELEMENT_NODE) {
        const element = child as HTMLElement;
        if (element.tagName === 'br') {
          accumulator.appendJsoupSpaceBoundary();
        }
      }
    }
    return accumulator.toTrimmedString();
  }

  private appendJsoupText(node: Node, accumulator: LegadoTextAccumulator): void {
    for (const child of node.childNodes) {
      if (child.nodeType === NodeType.TEXT_NODE) {
        const textNode = child as TextNode;
        accumulator.appendText(textNode.text, this.isPreserveWhitespace(textNode.parentNode));
        continue;
      }
      if (child.nodeType !== NodeType.ELEMENT_NODE) {
        continue;
      }

      const element = child as HTMLElement;
      if (element.tagName === 'br') {
        accumulator.appendJsoupSpaceBoundary();
        continue;
      }
      const isBlock = LegadoTextNormalization.isBlockTag(element.tagName);
      if (isBlock && accumulator.hasOutput() && !accumulator.endsWithSpace()) {
        accumulator.appendJsoupSpaceBoundary();
      }
      if (!LegadoTextNormalization.isDataTag(element.tagName)) {
        this.appendJsoupText(element, accumulator);
      }
      const nextSibling = element.nextSibling;
      if (isBlock && nextSibling !== null &&
        (nextSibling.nodeType === NodeType.TEXT_NODE ||
          (nextSibling.nodeType === NodeType.ELEMENT_NODE &&
            !LegadoTextNormalization.isFormatAsBlockTag((nextSibling as HTMLElement).tagName)))) {
        accumulator.appendJsoupSpaceBoundary();
      }
    }
  }

  private isPreserveWhitespace(node: Node | null): boolean {
    let current: Node | null = node;
    let depth = 0;
    while (current !== null && depth < 6) {
      if (current.nodeType === NodeType.ELEMENT_NODE &&
        LegadoTextNormalization.isPreserveWhitespaceTag((current as HTMLElement).tagName)) {
        return true;
      }
      current = current.parentNode;
      depth++;
    }
    return false;
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
    return this.selectAll(selector, false);
  }

  /**
   * 以 Jsoup Element.select 语义查询匹配元素。
   *
   * 标准 DOM querySelectorAll 只枚举当前节点的后代；Legado 的
   * AnalyzeByJSoup 则调用 Element.select，它会把当前 Element 本身作为
   * 候选节点。解析器合成的 root 代表 Jsoup Document 边界，不能作为
   * 普通元素返回。
   */
  select(selector: string): HTMLElement[] {
    return this.selectAll(selector, true);
  }

  private selectAll(selector: string, includeSelf: boolean): HTMLElement[] {
    const selectorGroups = Matcher.parseSelector(selector);
    if (selectorGroups.length === 0) {
      HtmlParserLogger.warn(`无效的选择器: "${selector}"`);
      return [];
    }
    const results: HTMLElement[] = [];
    const seen = new Set<HTMLElement>();
    
    for (const chain of selectorGroups) {
      const matches = this.matchSelectorChain(chain, 0, includeSelf);
      for (const match of matches) {
        if (!seen.has(match)) {
          seen.add(match);
          results.push(match);
        }
      }
    }

    // Jsoup Element.select returns selector-group unions in source order,
    // while retaining distinct element identity for equal outerHTML values.
    const documentOrder = this.getSelectionDocumentOrder(includeSelf);
    const documentPositions = new Map<HTMLElement, number>();
    for (let index = 0; index < documentOrder.length; index++) {
      documentPositions.set(documentOrder[index], index);
    }
    results.sort((left: HTMLElement, right: HTMLElement): number => {
      const leftPosition = documentPositions.get(left);
      const rightPosition = documentPositions.get(right);
      if (leftPosition === undefined || rightPosition === undefined) {
        return 0;
      }
      return leftPosition - rightPosition;
    });
    
    return results;
  }

  private getSelectionDocumentOrder(includeSelf: boolean): HTMLElement[] {
    const descendants = this.getElementsByTagName('*');
    if (!includeSelf || this.isSyntheticDocumentRoot()) {
      return descendants;
    }
    const results: HTMLElement[] = [this];
    for (const descendant of descendants) {
      results.push(descendant);
    }
    return results;
  }

  private isSyntheticDocumentRoot(): boolean {
    return this.tagName === 'root' && this.parentNode === null;
  }

  private isWithinSelectionScope(element: HTMLElement, includeSelf: boolean): boolean {
    if (element === this) {
      return includeSelf && !this.isSyntheticDocumentRoot();
    }

    let current: Node | null = element.parentNode;
    while (current !== null) {
      if (current === this) {
        return true;
      }
      current = current.parentNode;
    }
    return false;
  }

  /**
   * 匹配选择器链
   */
  private matchSelectorChain(chain: SelectorNode[], startIndex: number, includeSelf: boolean): HTMLElement[] {
    if (startIndex >= chain.length) return [];
    
    const currentNode = chain[startIndex];
    const isLast = startIndex === chain.length - 1;
    
    const descendants = this.getSelectionDocumentOrder(includeSelf);
    const matches: HTMLElement[] = [];
    
    for (const elem of descendants) {
      if (this.matchesSelectorPart(elem, currentNode.part)) {
        if (isLast) {
          matches.push(elem);
        } else {
          const combinator = currentNode.combinator;
          const nextMatches = this.matchNextInChain(elem, chain, startIndex + 1, combinator);
          for (const m of nextMatches) {
            if (this.isWithinSelectionScope(m, includeSelf)) {
              matches.push(m);
            }
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
    const isSyntheticDocumentParent = parent !== null &&
      parent.tagName === 'root' && parent.parentNode === null;
    if (isSyntheticDocumentParent &&
      (pseudo.name === 'first-child' || pseudo.name === 'last-child' ||
        pseudo.name === 'nth-child' || pseudo.name === 'nth-last-child' ||
        pseudo.name === 'only-child' ||
        pseudo.name === 'first-of-type' || pseudo.name === 'last-of-type' ||
        pseudo.name === 'only-of-type' || pseudo.name === 'nth-of-type' ||
        pseudo.name === 'nth-last-of-type')) {
      return false;
    }
    
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
    } else if (pseudo.name === 'nth-last-child') {
      if (!parent) return false;
      const siblingIndex = parent.children.indexOf(elem);
      if (siblingIndex < 0) return false;
      const indexFromEnd = parent.children.length - siblingIndex;
      return this.matchNthExpression(indexFromEnd, pseudo.argument);
    } else if (pseudo.name === 'first-of-type') {
      if (!parent) return false;
      return this.getElementTypeIndex(elem, parent) === 1;
    } else if (pseudo.name === 'last-of-type') {
      if (!parent) return false;
      const typeIndex = this.getElementTypeIndex(elem, parent);
      return typeIndex > 0 && typeIndex === this.getElementTypeCount(elem, parent);
    } else if (pseudo.name === 'only-of-type') {
      if (!parent) return false;
      return this.getElementTypeCount(elem, parent) === 1;
    } else if (pseudo.name === 'nth-of-type') {
      if (!parent) return false;
      const typeIndex = this.getElementTypeIndex(elem, parent);
      return typeIndex > 0 && this.matchNthExpression(typeIndex, pseudo.argument);
    } else if (pseudo.name === 'nth-last-of-type') {
      if (!parent) return false;
      const typeIndex = this.getElementTypeIndex(elem, parent);
      const typeCount = this.getElementTypeCount(elem, parent);
      const typeIndexFromEnd = typeCount - typeIndex + 1;
      return typeIndex > 0 && this.matchNthExpression(typeIndexFromEnd, pseudo.argument);
    } else if (pseudo.name === 'eq') {
      const index = this.parseIndexPseudoArgument(pseudo.argument);
      if (index === null) return false;
      return this.getElementSiblingIndex(elem, parent) === index;
    } else if (pseudo.name === 'lt') {
      const index = this.parseIndexPseudoArgument(pseudo.argument);
      if (index === null) return false;
      const siblingIndex = this.getElementSiblingIndex(elem, parent);
      return siblingIndex >= 0 && siblingIndex < index;
    } else if (pseudo.name === 'only-child') {
      if (!parent) return false;
      return parent.children.length === 1;
    } else if (pseudo.name === 'empty') {
      return this.matchesJsoupEmptyPseudo(elem);
    } else if (pseudo.name === 'contains') {
      return this.matchesPseudoContains(elem.text, pseudo.argument);
    } else if (pseudo.name === 'containsown') {
      return this.matchesPseudoContains(elem.ownText, pseudo.argument);
    } else if (pseudo.name === 'matches') {
      return this.matchesPseudoRegex(elem.text, pseudo.argument);
    } else if (pseudo.name === 'matchesown') {
      return this.matchesPseudoRegex(elem.ownText, pseudo.argument);
    } else if (pseudo.name === 'has') {
      const argument = this.normalizePseudoArgument(pseudo.argument);
      if (!argument) {
        return false;
      }
      if (argument.startsWith('>')) {
        const childSelector = argument.substring(1).trim();
        if (!childSelector) {
          return false;
        }
        return this.matchesHasDirectChildRelativeSelector(elem, childSelector);
      }
      return elem.querySelectorAll(argument).length > 0;
    } else if (pseudo.name === 'not') {
      const argument = this.normalizePseudoArgument(pseudo.argument);
      if (!argument) {
        return false;
      }
      if (this.selectorContainsInvalidRegexAttribute(argument)) {
        return false;
      }
      const selectorGroups = Matcher.parseSelector(argument);
      if (selectorGroups.length === 0) {
        return false;
      }
      for (const selectorGroup of selectorGroups) {
        if (this.matchesSelectorChainAtElement(elem, selectorGroup)) {
          return false;
        }
      }
      return true;
    }

    // Unknown Jsoup pseudo classes must fail closed. Returning true here
    // silently widens a selector and can make an invalid rule look readable.
    return false;
  }

  private matchesJsoupEmptyPseudo(elem: HTMLElement): boolean {
    for (const child of elem.childNodes) {
      if (child.nodeType === NodeType.TEXT_NODE) {
        if (!(child as TextNode).isWhitespace) return false;
        continue;
      }
      if (child.nodeType === NodeType.COMMENT_NODE) continue;
      return false;
    }
    return true;
  }

  /**
   * Evaluates a Jsoup relative selector against the direct children of an
   * element. The selector may continue below the direct child (for example
   * `>div span`), so matching only with child.matches() is insufficient.
   */
  private matchesHasDirectChildRelativeSelector(elem: HTMLElement, selector: string): boolean {
    const matches = elem.querySelectorAll(selector);
    for (const match of matches) {
      let current: HTMLElement | null = match;
      while (current !== null) {
        const parentNode = current.parentNode;
        if (parentNode === elem) {
          return true;
        }
        if (parentNode === null || parentNode.nodeType !== NodeType.ELEMENT_NODE) {
          break;
        }
        current = parentNode as HTMLElement;
      }
    }
    return false;
  }
  private selectorContainsInvalidRegexAttribute(selector: string): boolean {
    const selectorGroups = Matcher.parseSelector(selector);
    for (const group of selectorGroups) {
      for (const node of group) {
        for (const attribute of node.part.attributes) {
          if (!Matcher.isValidLegadoAttributeSelector(attribute)) {
            return true;
          }
        }
        for (const nestedPseudo of node.part.pseudoClasses) {
          if (nestedPseudo.name !== 'not' && nestedPseudo.name !== 'has') {
            continue;
          }
          let nestedArgument = this.normalizePseudoArgument(nestedPseudo.argument);
          if (nestedArgument.startsWith('>')) {
            nestedArgument = nestedArgument.substring(1).trim();
          }
          if (nestedArgument.length > 0 && this.selectorContainsInvalidRegexAttribute(nestedArgument)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  private matchesSelectorChainAtElement(elem: HTMLElement, chain: SelectorNode[]): boolean {
    if (chain.length === 0) {
      return false;
    }
    return this.matchesSelectorChainNode(elem, chain, chain.length - 1);
  }

  private matchesSelectorChainNode(elem: HTMLElement, chain: SelectorNode[], index: number): boolean {
    if (!this.matchesSelectorPart(elem, chain[index].part)) {
      return false;
    }
    if (index === 0) {
      return true;
    }

    const previousIndex = index - 1;
    const combinator = chain[previousIndex].combinator ?? Combinator.DESCENDANT;
    const parent = elem.parentNode !== null && elem.parentNode.nodeType === NodeType.ELEMENT_NODE
      ? elem.parentNode as HTMLElement
      : null;
    if (combinator === Combinator.CHILD) {
      return parent !== null && this.matchesSelectorChainNode(parent, chain, previousIndex);
    }
    if (combinator === Combinator.ADJACENT_SIBLING) {
      return parent !== null && parent.children.indexOf(elem) > 0
        ? this.matchesSelectorChainNode(parent.children[parent.children.indexOf(elem) - 1], chain, previousIndex)
        : false;
    }
    if (combinator === Combinator.GENERAL_SIBLING) {
      if (parent === null) {
        return false;
      }
      const siblingIndex = parent.children.indexOf(elem);
      for (let candidateIndex = siblingIndex - 1; candidateIndex >= 0; candidateIndex--) {
        if (this.matchesSelectorChainNode(parent.children[candidateIndex], chain, previousIndex)) {
          return true;
        }
      }
      return false;
    }

    let ancestor = parent;
    while (ancestor !== null) {
      if (this.matchesSelectorChainNode(ancestor, chain, previousIndex)) {
        return true;
      }
      ancestor = ancestor.parentNode !== null && ancestor.parentNode.nodeType === NodeType.ELEMENT_NODE
        ? ancestor.parentNode as HTMLElement
        : null;
    }
    return false;
  }

  private matchesPseudoContains(text: string, argument: string): boolean {
    const normalized = this.normalizePseudoArgument(argument);
    return text.includes(normalized);
  }

  private matchesPseudoRegex(text: string, argument: string): boolean {
    const normalized = this.normalizePseudoArgument(argument);
    const regexParts = this.parseLegadoRegexPrefix(normalized);
    try {
      return new RegExp(regexParts.pattern, regexParts.flags).test(text);
    } catch (error) {
      return false;
    }
  }

  private normalizePseudoArgument(argument: string): string {
    const trimmed = argument.trim();
    if (trimmed.length >= 2) {
      const first = trimmed[0];
      const last = trimmed[trimmed.length - 1];
      if ((first === '"' || first === "'") && first === last) {
        return trimmed.substring(1, trimmed.length - 1);
      }
    }
    return trimmed;
  }

  private parseLegadoRegexPrefix(pattern: string): LegadoRegexPrefix {
    const prefix = pattern.match(/^\(\?([imsu-]+)\)/);
    if (!prefix) {
      return { pattern: pattern, flags: '' };
    }
    let flags = '';
    for (const flag of prefix[1]) {
      if ((flag === 'i' || flag === 'm' || flag === 's' || flag === 'u') && !flags.includes(flag)) {
        flags += flag;
      }
    }
    return { pattern: pattern.substring(prefix[0].length), flags: flags };
  }

  /**
   * 匹配 :nth-child
   */
  private matchNthChild(elem: HTMLElement, parent: HTMLElement, argument: string): boolean {
    const index = parent.children.indexOf(elem) + 1;
    return this.matchNthExpression(index, argument);
  }

  private getElementSiblingIndex(elem: HTMLElement, parent: HTMLElement | null): number {
    if (!parent) return -1;
    return parent.children.indexOf(elem);
  }

  private getElementTypeIndex(elem: HTMLElement, parent: HTMLElement): number {
    let index = 0;
    for (const child of parent.children) {
      if (child.tagName === elem.tagName) {
        index++;
      }
      if (child === elem) {
        return child.tagName === elem.tagName ? index : 0;
      }
    }
    return 0;
  }

  private getElementTypeCount(elem: HTMLElement, parent: HTMLElement): number {
    let count = 0;
    for (const child of parent.children) {
      if (child.tagName === elem.tagName) {
        count++;
      }
    }
    return count;
  }

  private parseIndexPseudoArgument(argument: string): number | null {
    const normalized = argument.trim();
    if (!/^\d+$/.test(normalized)) {
      return null;
    }
    const value = parseInt(normalized, 10);
    return Number.isNaN(value) ? null : value;
  }

  /**
   * 匹配 nth 表达式
   */
  private matchNthExpression(index: number, expression: string): boolean {
    const expr = expression.replace(/\s+/g, '').toLowerCase();
    
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

    const formulaMatch = expr.match(/^([+-]?\d*)n([+-]?\d+)?$/);
    if (!formulaMatch) {
      return false;
    }
    const coefficientText = formulaMatch[1];
    const coefficient = coefficientText === '' || coefficientText === '+'
      ? 1
      : coefficientText === '-'
        ? -1
        : parseInt(coefficientText, 10);
    const offset = formulaMatch[2] ? parseInt(formulaMatch[2], 10) : 0;
    if (Number.isNaN(coefficient) || Number.isNaN(offset) || coefficient === 0) {
      return coefficient === 0 && index === offset;
    }
    const distance = index - offset;
    return distance * coefficient >= 0 && distance % coefficient === 0;
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
