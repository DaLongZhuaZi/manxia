/**
 * 变量替换引擎
 * 支持 {{variable}} 格式的变量替换
 */

import { logger } from '../../Utils/Logger';

const TAG = 'VariableReplacer';

/**
 * 变量上下文 - 使用ESObject代替索引签名
 */
export type VariableContext = ESObject;

/**
 * 变量替换器类
 */
export class VariableReplacer {
  /**
   * 替换字符串中的变量
   * @param template 模板字符串
   * @param context 变量上下文
   * @returns 替换后的字符串
   */
  static replace(template: string, context: ESObject): string {
    if (!template) {
      return template;
    }

    try {
      return template.replace(/\{\{([^}]+)\}\}/g, (match: string, key: string): string => {
        const trimmedKey = key.trim();
        
        // 支持嵌套属性: settings.imageQuality
        const value = VariableReplacer.getNestedValue(context, trimmedKey);
        
        if (value === undefined || value === null) {
          logger.warn(TAG, `变量未定义: ${trimmedKey}`);
          return match; // 保留原始占位符
        }

        return String(value);
      });
    } catch (error) {
      logger.error(TAG, '变量替换失败', String(error));
      return template;
    }
  }

  /**
   * 替换对象中的所有变量
   * @param obj 对象
   * @param context 变量上下文
   * @returns 替换后的对象
   */
  static replaceObject(obj: ESObject, context: ESObject): ESObject {
    if (typeof obj !== 'object' || obj === null) {
      return obj;
    }

    const result: ESObject = {};
    const keys = Object.keys(obj);

    for (const key of keys) {
      const value: ESObject | string | number | boolean | null | undefined = obj[key];

      if (typeof value === 'string') {
        result[key] = VariableReplacer.replace(value, context);
      } else if (typeof value === 'object' && value !== null) {
        if (Array.isArray(value)) {
          result[key] = value.map((item: ESObject): ESObject => {
            if (typeof item === 'string') {
              return VariableReplacer.replace(item, context);
            } else if (typeof item === 'object') {
              return VariableReplacer.replaceObject(item, context);
            }
            return item;
          });
        } else {
          result[key] = VariableReplacer.replaceObject(value as ESObject, context);
        }
      } else {
        result[key] = value;
      }
    }

    return result;
  }

  /**
   * 获取嵌套属性值
   */
  private static getNestedValue(obj: ESObject, path: string): string | number | boolean | undefined {
    const keys = path.split('.');
    let current: ESObject | string | number | boolean | undefined = obj;

    for (const key of keys) {
      if (current === null || current === undefined) {
        return undefined;
      }
      if (typeof current === 'object') {
        current = (current as ESObject)[key] as string | number | boolean | undefined;
      } else {
        return undefined;
      }
    }

    return current as string | number | boolean | undefined;
  }

  /**
   * 创建标准变量上下文
   */
  static createContext(params: ESObject): ESObject {
    const context: ESObject = {};

    // 复制所有参数 - 使用Object.keys代替for...in
    const keys = Object.keys(params);
    for (const key of keys) {
      const value: ESObject | string | number | boolean | null | undefined = params[key];
      if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
        context[key] = value;
      } else if (typeof value === 'object' && value !== null) {
        // 嵌套对象
        context[key] = JSON.stringify(value);
      }
    }

    return context;
  }

  /**
   * 合并多个上下文
   */
  static mergeContexts(...contexts: ESObject[]): ESObject {
    const merged: ESObject = {};

    for (let i = 0; i < contexts.length; i++) {
      const context: ESObject = contexts[i];
      const keys: string[] = Object.keys(context);
      for (const key of keys) {
        const value: ESObject | string | number | boolean | null | undefined = context[key];
        merged[key] = value;
      }
    }

    return merged;
  }
}

/**
 * 便捷函数
 */
export function replaceVariables(template: string, context: ESObject): string {
  return VariableReplacer.replace(template, context);
}

export function replaceObjectVariables(obj: ESObject, context: ESObject): ESObject {
  return VariableReplacer.replaceObject(obj, context);
}
