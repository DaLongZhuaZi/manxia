/**
 * CSS 选择器匹配器
 * 负责解析和匹配 CSS 选择器
 */

/**
 * 属性选择器
 */
export class AttributeSelector {
  name: string = '';
  operator: string = '';
  value: string = '';

  constructor(name: string, operator: string, value: string) {
    this.name = name;
    this.operator = operator;
    this.value = value;
  }
}

/**
 * 伪类选择器
 */
export class PseudoClass {
  name: string = '';
  argument: string = '';

  constructor(name: string, argument: string) {
    this.name = name;
    this.argument = argument;
  }
}

/**
 * 解析后的选择器部分
 */
export class SelectorPart {
  tagName: string = '';
  id: string = '';
  classes: string[] = [];
  attributes: AttributeSelector[] = [];
  pseudoClasses: PseudoClass[] = [];
}

/**
 * 选择器组合关系
 */
export enum Combinator {
  DESCENDANT = ' ',
  CHILD = '>',
  ADJACENT_SIBLING = '+',
  GENERAL_SIBLING = '~'
}

/**
 * 选择器链中的一个节点
 */
export class SelectorNode {
  part: SelectorPart = new SelectorPart();
  combinator: Combinator | null = null;

  constructor(part: SelectorPart, combinator: Combinator | null = null) {
    this.part = part;
    this.combinator = combinator;
  }
}

/**
 * 选择器部分解析结果
 */
class SelectorPartResult {
  part: SelectorPart;
  remaining: string;

  constructor(part: SelectorPart, remaining: string) {
    this.part = part;
    this.remaining = remaining;
  }
}

/**
 * 属性选择器解析结果
 */
class AttributeSelectorResult {
  attr: AttributeSelector;
  endIndex: number;

  constructor(attr: AttributeSelector, endIndex: number) {
    this.attr = attr;
    this.endIndex = endIndex;
  }
}

/**
 * 伪类解析结果
 */
class PseudoClassResult {
  pseudo: PseudoClass;
  endIndex: number;

  constructor(pseudo: PseudoClass, endIndex: number) {
    this.pseudo = pseudo;
    this.endIndex = endIndex;
  }
}

/**
 * CSS 选择器匹配器类
 */
export class Matcher {
  /**
   * 解析 CSS 选择器字符串
   */
  static parseSelector(selector: string): SelectorNode[][] {
    const trimmed = selector.trim();
    if (!trimmed) return [];

    const groups = Matcher.splitByComma(trimmed);
    const result: SelectorNode[][] = [];

    for (const group of groups) {
      const chain = Matcher.parseSelectorChain(group.trim());
      if (chain.length > 0) {
        result.push(chain);
      }
    }

    return result;
  }

  /**
   * 按逗号分割选择器
   */
  private static splitByComma(selector: string): string[] {
    const result: string[] = [];
    let current = '';
    let depth = 0;

    for (let i = 0; i < selector.length; i++) {
      const char = selector[i];
      if (char === '(' || char === '[') {
        depth++;
        current += char;
      } else if (char === ')' || char === ']') {
        depth--;
        current += char;
      } else if (char === ',' && depth === 0) {
        if (current.trim()) {
          result.push(current.trim());
        }
        current = '';
      } else {
        current += char;
      }
    }

    if (current.trim()) {
      result.push(current.trim());
    }

    return result;
  }

  /**
   * 解析单个选择器链
   */
  private static parseSelectorChain(selector: string): SelectorNode[] {
    const chain: SelectorNode[] = [];
    let remaining = selector.trim();

    while (remaining.length > 0) {
      remaining = remaining.trimStart();
      if (!remaining) break;

      let combinator: Combinator | null = null;
      if (chain.length > 0) {
        const firstChar = remaining[0];
        if (firstChar === '>') {
          combinator = Combinator.CHILD;
          remaining = remaining.substring(1).trimStart();
        } else if (firstChar === '+') {
          combinator = Combinator.ADJACENT_SIBLING;
          remaining = remaining.substring(1).trimStart();
        } else if (firstChar === '~') {
          combinator = Combinator.GENERAL_SIBLING;
          remaining = remaining.substring(1).trimStart();
        } else {
          combinator = Combinator.DESCENDANT;
        }

        if (chain.length > 0) {
          chain[chain.length - 1].combinator = combinator;
        }
      }

      const parseResult = Matcher.parseSelectorPart(remaining);
      if (!parseResult) break;

      chain.push(new SelectorNode(parseResult.part, null));
      remaining = parseResult.remaining;
    }

    return chain;
  }

  /**
   * 解析单个选择器部分
   */
  private static parseSelectorPart(selector: string): SelectorPartResult | null {
    const part = new SelectorPart();

    let i = 0;
    const len = selector.length;

    if (i < len && /[a-zA-Z*]/.test(selector[i])) {
      let tagName = '';
      while (i < len && /[a-zA-Z0-9*-]/.test(selector[i])) {
        tagName += selector[i];
        i++;
      }
      part.tagName = tagName.toLowerCase();
    }

    while (i < len) {
      const char = selector[i];

      if (char === '#') {
        i++;
        let id = '';
        while (i < len && /[a-zA-Z0-9_-]/.test(selector[i])) {
          id += selector[i];
          i++;
        }
        part.id = id;
      } else if (char === '.') {
        i++;
        let className = '';
        while (i < len && /[a-zA-Z0-9_-]/.test(selector[i])) {
          className += selector[i];
          i++;
        }
        if (className) {
          part.classes.push(className);
        }
      } else if (char === '[') {
        i++;
        const attrResult = Matcher.parseAttributeSelector(selector, i);
        if (attrResult) {
          part.attributes.push(attrResult.attr);
          i = attrResult.endIndex;
        }
      } else if (char === ':') {
        i++;
        if (i < len && selector[i] === ':') {
          i++;
        }
        const pseudoResult = Matcher.parsePseudoClass(selector, i);
        if (pseudoResult) {
          part.pseudoClasses.push(pseudoResult.pseudo);
          i = pseudoResult.endIndex;
        }
      } else if (/\s/.test(char) || char === '>' || char === '+' || char === '~' || char === ',') {
        break;
      } else {
        break;
      }
    }

    if (!part.tagName && !part.id && part.classes.length === 0 && 
        part.attributes.length === 0 && part.pseudoClasses.length === 0) {
      return null;
    }

    return new SelectorPartResult(part, selector.substring(i));
  }

  /**
   * 解析属性选择器
   */
  private static parseAttributeSelector(selector: string, startIndex: number): AttributeSelectorResult | null {
    let i = startIndex;
    const len = selector.length;

    let name = '';
    while (i < len && /[a-zA-Z0-9_-]/.test(selector[i])) {
      name += selector[i];
      i++;
    }

    if (!name) return null;

    while (i < len && /\s/.test(selector[i])) i++;

    let operator = '';
    let value = '';

    if (i < len && selector[i] !== ']') {
      if (selector[i] === '=' || selector[i] === '^' || selector[i] === '$' || 
          selector[i] === '*' || selector[i] === '~' || selector[i] === '|') {
        if (selector[i] !== '=') {
          operator = selector[i];
          i++;
        }
        if (i < len && selector[i] === '=') {
          operator += '=';
          i++;
        }
      }

      while (i < len && /\s/.test(selector[i])) i++;

      if (i < len && selector[i] !== ']') {
        const quote = selector[i];
        if (quote === '"' || quote === "'") {
          i++;
          while (i < len && selector[i] !== quote) {
            value += selector[i];
            i++;
          }
          if (i < len) i++;
        } else {
          while (i < len && selector[i] !== ']' && !/\s/.test(selector[i])) {
            value += selector[i];
            i++;
          }
        }
      }
    }

    while (i < len && /\s/.test(selector[i])) i++;

    if (i < len && selector[i] === ']') {
      i++;
    }

    const attr = new AttributeSelector(name.toLowerCase(), operator || '', value);
    return new AttributeSelectorResult(attr, i);
  }

  /**
   * 解析伪类选择器
   */
  private static parsePseudoClass(selector: string, startIndex: number): PseudoClassResult | null {
    let i = startIndex;
    const len = selector.length;

    let name = '';
    while (i < len && /[a-zA-Z0-9-]/.test(selector[i])) {
      name += selector[i];
      i++;
    }

    if (!name) return null;

    let argument = '';
    if (i < len && selector[i] === '(') {
      i++;
      let depth = 1;
      while (i < len && depth > 0) {
        if (selector[i] === '(') depth++;
        else if (selector[i] === ')') depth--;
        if (depth > 0) {
          argument += selector[i];
        }
        i++;
      }
    }

    const pseudo = new PseudoClass(name.toLowerCase(), argument.trim());
    return new PseudoClassResult(pseudo, i);
  }

  /**
   * 检查属性是否匹配
   */
  static matchAttribute(attrValue: string | undefined, selector: AttributeSelector): boolean {
    if (!selector.operator) {
      return attrValue !== undefined;
    }

    if (attrValue === undefined) return false;

    switch (selector.operator) {
      case '=':
        return attrValue === selector.value;
      case '^=':
        return attrValue.startsWith(selector.value);
      case '$=':
        return attrValue.endsWith(selector.value);
      case '*=':
        return attrValue.includes(selector.value);
      case '~=':
        return attrValue.split(/\s+/).includes(selector.value);
      case '|=':
        return attrValue === selector.value || attrValue.startsWith(selector.value + '-');
      default:
        return false;
    }
  }
}
