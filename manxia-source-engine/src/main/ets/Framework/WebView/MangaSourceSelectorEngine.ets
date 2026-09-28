/**
 * 漫画图源选择器引擎
 * 支持CSS选择器、XPath、文本匹配等多种选择方式
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  Selector,
  SelectorType,
  TextMatchType,
  MangaSourceError,
  MangaSourceErrorCode,
  TextSelector,
  AttributeSelector,
  CSSSelector,
  XPathSelector,
  RegexSelector,
  CompositeSelector
} from './MangaSourceTypes';

const TAG = 'MangaSourceSelectorEngine';

/**
 * 选择器匹配结果
 */
export interface SelectorResult {
  /** 是否找到匹配元素 */
  found: boolean;
  /** 匹配元素数量 */
  count: number;
  /** 第一个匹配元素的信息 */
  element?: ElementInfo;
  /** 所有匹配元素的信息 */
  elements?: ElementInfo[];
}

/**
 * 元素信息
 */
export interface Position {
  x: number;
  y: number;
  width: number;
  height: number;
}
export interface ElementInfo {
  /** 元素标签名 */
  tagName: string;
  /** 元素文本内容 */
  text: string;
  /** 元素属性 */
  attributes: Record<string, string>;
  /** 元素在页面中的位置 */
  position?: Position;
}

/**
 * 选择器执行上下文
 */
export interface SelectorContext {
  /** 是否调试模式 */
  debug: boolean;
  /** 超时时间 */
  timeout: number;
  /** 是否区分大小写 */
  caseSensitive: boolean;
}

/**
 * 选择器执行错误结果
 */
interface ErrorResult {
  found: false;
  count: 0;
  error: string;
}

/**
 * JavaScript执行结果联合类型
 */
type JSExecutionResult = SelectorResult | ErrorResult;

/**
 * 漫画图源选择器引擎
 */
export class MangaSourceSelectorEngine {


  /**
   * 执行选择器查询
   */
  async executeSelector(
    selector: Selector,
    context: SelectorContext,
    executeJS: (script: string) => Promise<Object>
  ): Promise<SelectorResult> {
    try {
      logger.debug(TAG, `执行选择器: ${selector.type}` + selector);

      let result: SelectorResult;

      switch (selector.type) {
        case SelectorType.CSS:
          result = await this.executeCSSSelector(selector, context, executeJS);
          break;
        case SelectorType.XPATH:
          result = await this.executeXPathSelector(selector, context, executeJS);
          break;
        case SelectorType.TEXT:
          result = await this.executeTextSelector(selector, context, executeJS);
          break;
        case SelectorType.ATTRIBUTE:
          result = await this.executeAttributeSelector(selector, context, executeJS);
          break;
        default:
          throw new MangaSourceError(
            MangaSourceErrorCode.INVALID_CONFIG,
            `不支持的选择器类型: ${(selector as Selector).type}`
          );
      }

      logger.debug(TAG, `选择器执行结果: 找到${result.count}个元素`);
      return result;

    } catch (error) {
      logger.error(TAG, '选择器执行失败' + error);
      throw error as Error;
    }
  }

  /**
   * 执行CSS选择器
   */
  private async executeCSSSelector(
    selector: Selector,
    context: SelectorContext,
    executeJS: (script: string) => Promise<Object>
  ): Promise<SelectorResult> {
    // 类型守卫：确保是CSS选择器
    if (selector.type !== SelectorType.CSS) {
      return {
        found: false,
        count: 0,
        error: 'Invalid selector type for CSS execution'
      } as ErrorResult;
    }
    
    const cssSelector = selector as CSSSelector;
    const script = `
      (function() {
        try {
          const elements = Array.from(document.querySelectorAll('${cssSelector.value}'));
          
          const getElementInfo = (element) => {
            const rect = element.getBoundingClientRect();
            return {
              tagName: element.tagName.toLowerCase(),
              text: element.textContent?.trim() || '',
              attributes: Object.fromEntries(
                Array.from(element.attributes).map(attr => [attr.name, attr.value])
              ),
              position: {
                x: rect.left,
                y: rect.top,
                width: rect.width,
                height: rect.height
              }
            };
          };
          
          const elementInfos = elements.map(getElementInfo);
          
          return {
            found: elements.length > 0,
            count: elements.length,
            element: elementInfos[0] || null,
            elements: elementInfos
          };
        } catch (error) {
          return {
            found: false,
            count: 0,
            error: error.message
          };
        }
      })();
    `;

    const result = await executeJS(script) as JSExecutionResult;
    
    // 检查结果是否包含错误
    const resultKeys = Object.keys(result);
    if (resultKeys.includes('error')) {
      const errorResult = result as ErrorResult;
      throw new MangaSourceError(
        MangaSourceErrorCode.SELECTOR_ERROR,
        `CSS选择器执行失败: ${errorResult.error}`
      );
    }

    return result as SelectorResult;
  }

  /**
   * 执行XPath选择器
   */
  private async executeXPathSelector(
    selector: Selector,
    context: SelectorContext,
    executeJS: (script: string) => Promise<Object>
  ): Promise<SelectorResult> {
    // 类型守卫：确保是XPath选择器
    if (selector.type !== SelectorType.XPATH) {
      return {
        found: false,
        count: 0,
        error: 'Invalid selector type for XPath execution'
      } as ErrorResult;
    }
    
    const xpathSelector = selector as XPathSelector;
    const script = `
      (function() {
        try {
          const xpath = '${xpathSelector.value}';
          const result = document.evaluate(
            xpath,
            document,
            null,
            XPathResult.ORDERED_NODE_SNAPSHOT_TYPE,
            null
          );
          
          const elements = [];
          for (let i = 0; i < result.snapshotLength; i++) {
            elements.push(result.snapshotItem(i));
          }
          
          const getElementInfo = (element) => {
            const rect = element.getBoundingClientRect();
            return {
              tagName: element.tagName ? element.tagName.toLowerCase() : 'text',
              text: element.textContent?.trim() || '',
              attributes: element.attributes ? Object.fromEntries(
                Array.from(element.attributes).map(attr => [attr.name, attr.value])
              ) : {},
              position: {
                x: rect.left,
                y: rect.top,
                width: rect.width,
                height: rect.height
              }
            };
          };
          
          const elementInfos = elements.map(getElementInfo);
          
          return {
            found: elements.length > 0,
            count: elements.length,
            element: elementInfos[0] || null,
            elements: elementInfos
          };
        } catch (error) {
          return {
            found: false,
            count: 0,
            error: error.message
          };
        }
      })();
    `;

    const result = await executeJS(script) as JSExecutionResult;
    
    // 检查结果是否包含错误
    const resultKeys = Object.keys(result);
    if (resultKeys.includes('error')) {
      const errorResult = result as ErrorResult;
      throw new MangaSourceError(
        MangaSourceErrorCode.SELECTOR_ERROR,
        `XPath选择器执行失败: ${errorResult.error}`
      );
    }

    return result as SelectorResult;
  }

  /**
   * 执行文本选择器
   */
  private async executeTextSelector(
    selector: Selector,
    context: SelectorContext,
    executeJS: (script: string) => Promise<Object>
  ): Promise<SelectorResult> {
    // 类型安全的属性访问
    const textSelector = selector as TextSelector;
    const matchType = textSelector.textMatch || TextMatchType.CONTAINS;
    const caseSensitive = context.caseSensitive;
    
    const script = `
      (function() {
        try {
          const searchText = '${textSelector.value}';
          const matchType = '${matchType}';
          const caseSensitive = ${caseSensitive};
          
          const allElements = Array.from(document.querySelectorAll('*'));
          const matchingElements = [];
          
          const textMatches = (elementText, searchText, matchType, caseSensitive) => {
            const text = caseSensitive ? elementText : elementText.toLowerCase();
            const search = caseSensitive ? searchText : searchText.toLowerCase();
            
            switch (matchType) {
              case 'exact':
                return text === search;
              case 'contains':
                return text.includes(search);
              case 'starts_with':
                return text.startsWith(search);
              case 'ends_with':
                return text.endsWith(search);
              case 'regex':
                try {
                  const regex = new RegExp(search, caseSensitive ? 'g' : 'gi');
                  return regex.test(text);
                } catch (e) {
                  return false;
                }
              default:
                return text.includes(search);
            }
          };
          
          for (const element of allElements) {
            const elementText = element.textContent?.trim() || '';
            if (elementText && textMatches(elementText, searchText, matchType, caseSensitive)) {
              // 确保元素不包含其他匹配的子元素（避免重复）
              const hasMatchingChild = Array.from(element.children).some(child => {
                const childText = child.textContent?.trim() || '';
                return childText && textMatches(childText, searchText, matchType, caseSensitive);
              });
              
              if (!hasMatchingChild) {
                matchingElements.push(element);
              }
            }
          }
          
          const getElementInfo = (element) => {
            const rect = element.getBoundingClientRect();
            return {
              tagName: element.tagName.toLowerCase(),
              text: element.textContent?.trim() || '',
              attributes: Object.fromEntries(
                Array.from(element.attributes).map(attr => [attr.name, attr.value])
              ),
              position: {
                x: rect.left,
                y: rect.top,
                width: rect.width,
                height: rect.height
              }
            };
          };
          
          const elementInfos = matchingElements.map(getElementInfo);
          
          return {
            found: matchingElements.length > 0,
            count: matchingElements.length,
            element: elementInfos[0] || null,
            elements: elementInfos
          };
        } catch (error) {
          return {
            found: false,
            count: 0,
            error: error.message
          };
        }
      })();
    `;

    const result = await executeJS(script) as JSExecutionResult;
    
    // 检查结果是否包含错误
    const resultKeys = Object.keys(result);
    if (resultKeys.includes('error')) {
      const errorResult = result as ErrorResult;
      throw new MangaSourceError(
        MangaSourceErrorCode.SELECTOR_ERROR,
        `文本选择器执行失败: ${errorResult.error}`
      );
    }

    return result as SelectorResult;
  }

  /**
   * 执行属性选择器
   */
  private async executeAttributeSelector(
    selector: Selector,
    context: SelectorContext,
    executeJS: (script: string) => Promise<Object>
  ): Promise<SelectorResult> {
    // 类型安全的属性访问
    const attributeSelector = selector as AttributeSelector;
    if (!attributeSelector.attribute) {
      throw new MangaSourceError(
        MangaSourceErrorCode.INVALID_CONFIG,
        '属性选择器缺少attribute参数'
      );
    }

    const matchType = attributeSelector.textMatch || TextMatchType.CONTAINS;
    const caseSensitive = context.caseSensitive;
    
    const script = `
      (function() {
        try {
          const attributeName = '${attributeSelector.attribute}';
          const targetValue = '${attributeSelector.value}';
          const matchType = '${matchType}';
          const caseSensitive = ${caseSensitive};
          
          const allElements = Array.from(document.querySelectorAll('*'));
          const matchingElements = [];
          
          const valueMatches = (attrValue, searchValue, matchType, caseSensitive) => {
            if (!attrValue) return false;
            
            const value = caseSensitive ? attrValue : attrValue.toLowerCase();
            const search = caseSensitive ? searchValue : searchValue.toLowerCase();
            
            switch (matchType) {
              case 'exact':
                return value === search;
              case 'contains':
                return value.includes(search);
              case 'starts_with':
                return value.startsWith(search);
              case 'ends_with':
                return value.endsWith(search);
              case 'regex':
                try {
                  const regex = new RegExp(search, caseSensitive ? 'g' : 'gi');
                  return regex.test(value);
                } catch (e) {
                  return false;
                }
              default:
                return value.includes(search);
            }
          };
          
          for (const element of allElements) {
            const attrValue = element.getAttribute(attributeName);
            if (attrValue && valueMatches(attrValue, searchValue, matchType, caseSensitive)) {
              matchingElements.push(element);
            }
          }
          
          const getElementInfo = (element) => {
            const rect = element.getBoundingClientRect();
            return {
              tagName: element.tagName.toLowerCase(),
              text: element.textContent?.trim() || '',
              attributes: Object.fromEntries(
                Array.from(element.attributes).map(attr => [attr.name, attr.value])
              ),
              position: {
                x: rect.left,
                y: rect.top,
                width: rect.width,
                height: rect.height
              }
            };
          };
          
          const elementInfos = matchingElements.map(getElementInfo);
          
          return {
            found: matchingElements.length > 0,
            count: matchingElements.length,
            element: elementInfos[0] || null,
            elements: elementInfos
          };
        } catch (error) {
          return {
            found: false,
            count: 0,
            error: error.message
          };
        }
      })();
    `;

    const result = await executeJS(script) as JSExecutionResult;
    
    // 检查结果是否包含错误
    const resultKeys = Object.keys(result);
    if (resultKeys.includes('error')) {
      const errorResult = result as ErrorResult;
      throw new MangaSourceError(
        MangaSourceErrorCode.SELECTOR_ERROR,
        `属性选择器执行失败: ${errorResult.error}`
      );
    }

    return result as SelectorResult;
  }

  /**
   * 构建复合选择器
   * 支持多个选择器的组合查询
   */
  async executeCompositeSelector(
    selectors: Selector[],
    operator: 'AND' | 'OR',
    context: SelectorContext,
    executeJS: (script: string) => Promise<Object>
  ): Promise<SelectorResult> {
    const results: SelectorResult[] = [];
    
    for (const selector of selectors) {
      const result = await this.executeSelector(selector, context, executeJS);
      results.push(result);
    }

    if (operator === 'AND') {
      // 所有选择器都必须找到元素
      const allFound = results.every(r => r.found);
      const totalCount = allFound ? Math.min(...results.map(r => r.count)) : 0;
      
      return {
        found: allFound,
        count: totalCount,
        element: allFound ? results[0].element : undefined,
        elements: allFound ? this.intersectElements(results) : []
      };
    } else {
      // 任一选择器找到元素即可
      const anyFound = results.some(r => r.found);
      const totalCount = results.reduce((sum, r) => sum + r.count, 0);
      const allElements = results.flatMap(r => r.elements || []);
      
      return {
        found: anyFound,
        count: totalCount,
        element: allElements[0],
        elements: allElements
      };
    }
  }

  /**
   * 获取元素的交集
   */
  private intersectElements(results: SelectorResult[]): ElementInfo[] {
    if (results.length === 0) return [];
    if (results.length === 1) return results[0].elements || [];

    // 简化实现：基于元素位置进行交集计算
    let intersection = results[0].elements || [];
    
    for (let i = 1; i < results.length; i++) {
      const currentElements = results[i].elements || [];
      intersection = intersection.filter(elem1 => 
        currentElements.some(elem2 => 
          elem1.position?.x === elem2.position?.x &&
          elem1.position?.y === elem2.position?.y
        )
      );
    }

    return intersection;
  }

  /**
   * 验证选择器配置
   */
  validateSelector(selector: Selector): boolean {
    if (!selector.type) {
      return false;
    }

    // 不同类型的选择器有不同的必需字段
    switch (selector.type) {
      case SelectorType.CSS:
      case SelectorType.XPATH:
        return !!(selector as CSSSelector | XPathSelector).value;
      case SelectorType.TEXT:
        return !!(selector as TextSelector).value;
      case SelectorType.ATTRIBUTE:
        return !!(selector as AttributeSelector).attribute;
      case SelectorType.REGEX:
        return !!(selector as RegexSelector).pattern;
      case SelectorType.COMPOSITE:
        return !!(selector as CompositeSelector).selectors;
      default:
        return false;
    }
  }

  /**
   * 原始验证方法（已废弃，保留兼容性）
   */
  private validateSelectorLegacy(selector: Selector): boolean {
    if (!selector.type) {
      return false;
    }

    switch (selector.type) {
      case SelectorType.CSS:
        return this.validateCSSSelector(selector.value);
      case SelectorType.XPATH:
        return this.validateXPathSelector(selector.value);
      case SelectorType.TEXT:
        return selector.value.length > 0;
      case SelectorType.ATTRIBUTE:
        return selector.attribute !== undefined && selector.value.length > 0;
      default:
        return false;
    }
  }

  /**
   * 验证CSS选择器语法
   */
  private validateCSSSelector(selector: string): boolean {
    try {
      // 简单的CSS选择器语法检查
      // 在HarmonyOS环境中，无法直接使用document.querySelector进行验证
      // 这里进行基本的语法检查
      if (!selector || selector.trim().length === 0) {
        return false;
      }
      // 检查是否包含基本的CSS选择器字符
      const validChars = /^[a-zA-Z0-9\s\.\#\[\]\:\-_,>+~*="'()]+$/;
      return validChars.test(selector);
    } catch (error) {
      return false;
    }
  }

  /**
   * 验证XPath选择器语法
   */
  private validateXPathSelector(xpath: string): boolean {
    try {
      // 简单的XPath语法检查
      // 在HarmonyOS环境中，无法直接使用document.evaluate进行验证
      // 这里进行基本的语法检查
      if (!xpath || xpath.trim().length === 0) {
        return false;
      }
      // 检查是否包含基本的XPath语法字符
      const validChars = /^[a-zA-Z0-9\s\/\[\]@\.\:\-_='"()]+$/;
      return validChars.test(xpath);
    } catch (error) {
      return false;
    }
  }
}