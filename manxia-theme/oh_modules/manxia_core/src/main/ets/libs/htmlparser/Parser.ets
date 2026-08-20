/**
 * HTML 解析器
 * 将 HTML 字符串解析为 DOM 树
 * 
 * 基于 node-html-parser 设计，完全使用 ArkTS 实现
 * 支持完整的 HTML5 解析和 CSS 选择器查询
 */

import { NodeType } from './NodeType';
import { Node } from './Node';
import { TextNode } from './TextNode';
import { CommentNode } from './CommentNode';
import { HTMLElement, Attributes } from './HTMLElement';
import { HtmlParserLogger } from './HtmlParserLogger';
import { HtmlEntities } from './HtmlEntities';

/**
 * 解析选项类
 */
export class ParseOptions {
  lowerCaseTagName: boolean = true;
  comment: boolean = true;
  fixNestedTags: boolean = true;
  voidTags: string[] = ['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 
                        'link', 'meta', 'param', 'source', 'track', 'wbr'];
  blockTextTags: string[] = ['script', 'noscript', 'style'];
}

/**
 * 属性解析结果
 */
class AttributeParseResult {
  attrs: Attributes;
  rawAttrs: string;

  constructor(attrs: Attributes, rawAttrs: string) {
    this.attrs = attrs;
    this.rawAttrs = rawAttrs;
  }
}

/**
 * HTML 解析器类
 */
export class Parser {
  private options: ParseOptions;
  private pos: number = 0;
  private html: string = '';
  
  constructor(options?: ParseOptions) {
    this.options = options || new ParseOptions();
  }
  
  /**
   * 解析 HTML 字符串
   */
  parse(html: string): HTMLElement {
    const startTime = Date.now();
    HtmlParserLogger.parseStart(html.length);
    
    this.html = html;
    this.pos = 0;
    
    const rootRange: [number, number] = [0, html.length];
    const root = new HTMLElement('root', null, '', null, rootRange);
    
    this.parseContent(root);
    
    const duration = Date.now() - startTime;
    const elementCount = this.countElements(root);
    HtmlParserLogger.parseComplete(elementCount, duration);
    
    return root;
  }
  
  /**
   * 统计元素数量
   */
  private countElements(root: HTMLElement): number {
    let count = 0;
    const traverse = (node: Node): void => {
      if (node.nodeType === NodeType.ELEMENT_NODE) {
        count++;
        for (const child of node.childNodes) {
          traverse(child);
        }
      }
    };
    traverse(root);
    return count;
  }
  
  /**
   * 解析内容
   */
  private parseContent(parent: HTMLElement): void {
    while (this.pos < this.html.length) {
      const char = this.html[this.pos];
      
      if (char === '<') {
        if (this.html.substring(this.pos, this.pos + 4) === '<!--') {
          this.parseComment(parent);
        } else if (this.html.substring(this.pos, this.pos + 9).toLowerCase() === '<!doctype') {
          this.skipDoctype();
        } else if (this.html[this.pos + 1] === '/') {
          break;
        } else if (this.html[this.pos + 1] === '!') {
          this.skipDeclaration();
        } else {
          const element = this.parseElement();
          if (element) {
            element.parentNode = parent;
            parent.childNodes.push(element);
          }
        }
      } else {
        this.parseText(parent);
      }
    }
  }
  
  /**
   * 解析文本节点
   */
  private parseText(parent: HTMLElement): void {
    const start = this.pos;
    let text = '';
    
    while (this.pos < this.html.length && this.html[this.pos] !== '<') {
      text += this.html[this.pos];
      this.pos++;
    }
    
    if (text) {
      const textRange: [number, number] = [start, this.pos];
      const textNode = new TextNode(text, parent, textRange);
      parent.childNodes.push(textNode);
    }
  }
  
  /**
   * 解析注释
   */
  private parseComment(parent: HTMLElement): void {
    if (!this.options.comment) {
      const endIndex = this.html.indexOf('-->', this.pos + 4);
      this.pos = endIndex >= 0 ? endIndex + 3 : this.html.length;
      return;
    }
    
    const start = this.pos;
    this.pos += 4;
    
    let comment = '';
    while (this.pos < this.html.length) {
      if (this.html.substring(this.pos, this.pos + 3) === '-->') {
        this.pos += 3;
        break;
      }
      comment += this.html[this.pos];
      this.pos++;
    }
    
    const commentRange: [number, number] = [start, this.pos];
    const commentNode = new CommentNode(comment, parent, commentRange);
    parent.childNodes.push(commentNode);
  }
  
  /**
   * 跳过 DOCTYPE
   */
  private skipDoctype(): void {
    const endIndex = this.html.indexOf('>', this.pos);
    this.pos = endIndex >= 0 ? endIndex + 1 : this.html.length;
  }
  
  /**
   * 跳过声明
   */
  private skipDeclaration(): void {
    const endIndex = this.html.indexOf('>', this.pos);
    this.pos = endIndex >= 0 ? endIndex + 1 : this.html.length;
  }
  
  /**
   * 解析元素
   */
  private parseElement(): HTMLElement | null {
    const start = this.pos;
    this.pos++;
    
    let tagName = '';
    while (this.pos < this.html.length && /[a-zA-Z0-9-]/.test(this.html[this.pos])) {
      tagName += this.html[this.pos];
      this.pos++;
    }
    
    if (!tagName) {
      return null;
    }
    
    const attrResult = this.parseAttributes();
    
    this.skipWhitespace();
    
    let selfClosing = false;
    if (this.html[this.pos] === '/') {
      selfClosing = true;
      this.pos++;
    }
    
    if (this.html[this.pos] === '>') {
      this.pos++;
    }
    
    const lowerTagName = tagName.toLowerCase();
    const isVoidTag = this.options.voidTags.includes(lowerTagName) || selfClosing;
    
    const elementRange: [number, number] = [start, this.pos];
    const element = new HTMLElement(tagName, attrResult.attrs, attrResult.rawAttrs, null, elementRange, isVoidTag);
    
    if (!isVoidTag) {
      const isBlockText = this.options.blockTextTags.includes(lowerTagName);
      
      if (isBlockText) {
        this.parseRawText(element, lowerTagName);
      } else {
        this.parseContent(element);
      }
      
      this.parseEndTag(lowerTagName);
    }
    
    element.range[1] = this.pos;
    return element;
  }
  
  /**
   * 解析属性
   */
  private parseAttributes(): AttributeParseResult {
    const attrs = new Attributes();
    const startPos = this.pos;
    
    while (this.pos < this.html.length) {
      this.skipWhitespace();
      
      const char = this.html[this.pos];
      if (char === '>' || char === '/' || !char) {
        break;
      }
      
      let attrName = '';
      while (this.pos < this.html.length && /[a-zA-Z0-9_:-]/.test(this.html[this.pos])) {
        attrName += this.html[this.pos];
        this.pos++;
      }
      
      if (!attrName) {
        this.pos++;
        continue;
      }
      
      this.skipWhitespace();
      
      let attrValue = '';
      if (this.html[this.pos] === '=') {
        this.pos++;
        this.skipWhitespace();
        
        const quote = this.html[this.pos];
        if (quote === '"' || quote === "'") {
          this.pos++;
          while (this.pos < this.html.length && this.html[this.pos] !== quote) {
            attrValue += this.html[this.pos];
            this.pos++;
          }
          if (this.pos < this.html.length) {
            this.pos++;
          }
        } else {
          while (this.pos < this.html.length && !/[\s>\/]/.test(this.html[this.pos])) {
            attrValue += this.html[this.pos];
            this.pos++;
          }
        }
      }
      
      attrs.set(attrName.toLowerCase(), HtmlEntities.decodeAttribute(attrValue));
    }
    
    const rawAttrs = this.html.substring(startPos, this.pos).trim();
    return new AttributeParseResult(attrs, rawAttrs);
  }
  
  /**
   * 解析原始文本内容
   * 优化：避免在循环中重复调用substring和toLowerCase，使用indexOf查找结束标签
   */
  private parseRawText(element: HTMLElement, tagName: string): void {
    const endTag = `</${tagName}`;
    const start = this.pos;
    
    // 优化：使用indexOf查找结束标签位置，避免逐字符遍历
    // 先尝试精确匹配
    let endPos = this.html.indexOf(endTag, this.pos);
    
    // 如果精确匹配失败，尝试不区分大小写匹配
    if (endPos === -1) {
      const htmlLower = this.html.toLowerCase();
      const endTagLower = endTag.toLowerCase();
      endPos = htmlLower.indexOf(endTagLower, this.pos);
    }
    
    if (endPos === -1) {
      // 没有找到结束标签，取剩余所有内容
      endPos = this.html.length;
    }
    
    const text = this.html.substring(start, endPos);
    this.pos = endPos;
    
    if (text) {
      const textRange: [number, number] = [start, this.pos];
      const textNode = new TextNode(text, element, textRange);
      element.childNodes.push(textNode);
    }
  }
  
  /**
   * 解析结束标签
   */
  private parseEndTag(_expectedTagName: string): void {
    if (this.html.substring(this.pos, this.pos + 2) !== '</') {
      return;
    }
    
    this.pos += 2;
    
    while (this.pos < this.html.length && /[a-zA-Z0-9-]/.test(this.html[this.pos])) {
      this.pos++;
    }
    
    this.skipWhitespace();
    if (this.html[this.pos] === '>') {
      this.pos++;
    }
  }
  
  /**
   * 跳过空白字符
   */
  private skipWhitespace(): void {
    while (this.pos < this.html.length && /\s/.test(this.html[this.pos])) {
      this.pos++;
    }
  }
}

/**
 * 便捷解析函数
 */
export function parse(html: string, options?: ParseOptions): HTMLElement {
  const parser = new Parser(options);
  return parser.parse(html);
}
