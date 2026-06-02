/**
 * JSONPath解析器
 * 简化版JSONPath实现，支持基本的路径表达式
 */

import { logger } from '../../Utils/Logger';

const TAG = 'JSONPathParser';

/**
 * JSONPath解析结果
 */
export type JSONPathResult = string | number | boolean | null | ESObject | ESObject[];

/**
 * JSONPath解析器类
 */
export class JSONPathParser {
  /**
   * 解析JSONPath表达式
   * @param data JSON数据
   * @param path JSONPath表达式
   * @returns 解析结果
   */
  static parse(data: ESObject, path: string): JSONPathResult {
    try {
      // 移除开头的$
      let normalizedPath = path.trim();
      if (normalizedPath.startsWith('$')) {
        normalizedPath = normalizedPath.substring(1);
      }
      if (normalizedPath.startsWith('.')) {
        normalizedPath = normalizedPath.substring(1);
      }

      // 空路径返回整个数据
      if (!normalizedPath) {
        return data;
      }

      // 分割路径
      const segments = JSONPathParser.parsePathSegments(normalizedPath);
      
      // 逐段解析
      let current: JSONPathResult = data;
      for (const segment of segments) {
        current = JSONPathParser.applySegment(current, segment);
        if (current === null || current === undefined) {
          return null;
        }
      }

      return current;
    } catch (error) {
      logger.error(TAG, `JSONPath解析失败: ${path}`, String(error));
      return null;
    }
  }

  /**
   * 解析路径段
   */
  private static parsePathSegments(path: string): string[] {
    const segments: string[] = [];
    let current = '';
    let inBracket = false;

    for (let i = 0; i < path.length; i++) {
      const char = path[i];

      if (char === '[') {
        if (current) {
          segments.push(current);
          current = '';
        }
        inBracket = true;
      } else if (char === ']') {
        if (inBracket && current) {
          segments.push(`[${current}]`);
          current = '';
        }
        inBracket = false;
      } else if (char === '.' && !inBracket) {
        if (current) {
          segments.push(current);
          current = '';
        }
      } else {
        current += char;
      }
    }

    if (current) {
      segments.push(current);
    }

    return segments;
  }

  /**
   * 应用单个路径段
   */
  private static applySegment(data: JSONPathResult, segment: string): JSONPathResult {
    if (data === null || data === undefined) {
      return null;
    }

    // 数组索引: [0], [1], etc.
    if (segment.startsWith('[') && segment.endsWith(']')) {
      const inner = segment.substring(1, segment.length - 1);
      
      // 通配符: [*]
      if (inner === '*') {
        if (Array.isArray(data)) {
          return data;
        }
        return null;
      }

      // 数字索引
      const index = parseInt(inner, 10);
      if (!isNaN(index)) {
        if (Array.isArray(data)) {
          return data[index] ?? null;
        }
        return null;
      }

      // 字符串键（带引号）
      const key = inner.replace(/^['"]|['"]$/g, '');
      if (typeof data === 'object' && data !== null) {
        return (data as ESObject)[key] ?? null;
      }
      return null;
    }

    // 对象属性
    if (typeof data === 'object' && data !== null && !Array.isArray(data)) {
      return (data as ESObject)[segment] ?? null;
    }

    return null;
  }

  /**
   * 批量解析（用于数组）
   * @param data JSON数据
   * @param path JSONPath表达式
   * @returns 数组结果
   */
  static parseArray(data: ESObject, path: string): ESObject[] {
    const result: JSONPathResult = JSONPathParser.parse(data, path);
    if (Array.isArray(result)) {
      return result;
    }
    if (result !== null && result !== undefined) {
      return [result as ESObject];
    }
    return [];
  }

  /**
   * 解析字符串值
   */
  static parseString(data: ESObject, path: string): string {
    const result: JSONPathResult = JSONPathParser.parse(data, path);
    if (result === null || result === undefined) {
      return '';
    }
    return String(result);
  }

  /**
   * 解析数字值
   */
  static parseNumber(data: ESObject, path: string): number {
    const result: JSONPathResult = JSONPathParser.parse(data, path);
    if (typeof result === 'number') {
      return result;
    }
    if (typeof result === 'string') {
      const num = parseFloat(result);
      return isNaN(num) ? 0 : num;
    }
    return 0;
  }

  /**
   * 解析布尔值
   */
  static parseBoolean(data: ESObject, path: string): boolean {
    const result: JSONPathResult = JSONPathParser.parse(data, path);
    if (typeof result === 'boolean') {
      return result;
    }
    if (typeof result === 'string') {
      return result.toLowerCase() === 'true';
    }
    if (typeof result === 'number') {
      return result !== 0;
    }
    return false;
  }

  /**
   * 测试JSONPath表达式
   */
  static test(data: ESObject, path: string): boolean {
    try {
      const result: JSONPathResult = JSONPathParser.parse(data, path);
      return result !== null && result !== undefined;
    } catch {
      return false;
    }
  }
}

/**
 * 便捷函数
 */
export function jsonPath(data: ESObject, path: string): JSONPathResult {
  return JSONPathParser.parse(data, path);
}

export function jsonPathArray(data: ESObject, path: string): ESObject[] {
  return JSONPathParser.parseArray(data, path);
}

export function jsonPathString(data: ESObject, path: string): string {
  return JSONPathParser.parseString(data, path);
}

export function jsonPathNumber(data: ESObject, path: string): number {
  return JSONPathParser.parseNumber(data, path);
}

export function jsonPathBoolean(data: ESObject, path: string): boolean {
  return JSONPathParser.parseBoolean(data, path);
}
