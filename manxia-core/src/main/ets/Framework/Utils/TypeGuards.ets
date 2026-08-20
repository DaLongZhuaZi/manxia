// 文件路径: src/main/ets/Framework/Utils/TypeGuards.ets
/**
 * 类型守卫工具类
 * 提供运行时类型检查功能，确保数据类型的安全性
 */

import { logger } from '../../Utils/Logger';
import { MangaStatus, DownloadStatus } from '../Types/StatusEnums';

const TAG = 'TypeGuards';

/**
 * 类型检查配置接口
 */
interface ITypeCheckConfig {
  value: Object;
  guard: (val: Object) => boolean;
  name: string;
}

/**
 * 类型守卫工具类
 * 提供运行时类型检查功能，确保数据类型的安全性
 */
export class TypeGuards {

  /**
   * 检查值是否为字符串
   * @param value - 要检查的值
   * @returns 是否为字符串
   */
  static isString(value: Object): boolean {
    return typeof value === 'string';
  }

  /**
   * 检查值是否为非空字符串
   * @param value - 要检查的值
   * @returns 是否为非空字符串
   */
  static isNonEmptyString(value: Object): boolean {
    if (!TypeGuards.isString(value)) {
      return false;
    }
    const strValue = value as string;
    return strValue.trim().length > 0;
  }

  /**
   * 检查值是否为数字
   * @param value - 要检查的值
   * @returns 是否为数字
   */
  static isNumber(value: Object): boolean {
    return typeof value === 'number' && !isNaN(value as number);
  }

  /**
   * 检查值是否为正数
   * @param value - 要检查的值
   * @returns 是否为正数
   */
  static isPositiveNumber(value: Object): boolean {
    if (!TypeGuards.isNumber(value)) {
      return false;
    }
    const numValue = value as number;
    return numValue > 0;
  }

  /**
   * 检查值是否为非负数
   * @param value - 要检查的值
   * @returns 是否为非负数
   */
  static isNonNegativeNumber(value: Object): boolean {
    if (!TypeGuards.isNumber(value)) {
      return false;
    }
    const numValue = value as number;
    return numValue >= 0;
  }

  /**
   * 检查值是否为整数
   * @param value - 要检查的值
   * @returns 是否为整数
   */
  static isInteger(value: Object): boolean {
    if (!TypeGuards.isNumber(value)) {
      return false;
    }
    const numValue = value as number;
    return Number.isInteger(numValue);
  }

  /**
   * 检查值是否为布尔值
   * @param value - 要检查的值
   * @returns 是否为布尔值
   */
  static isBoolean(value: Object): boolean {
    return typeof value === 'boolean';
  }

  /**
   * 检查值是否为数组
   * @param value - 要检查的值
   * @returns 是否为数组
   */
  static isArray(value: Object): boolean {
    return Array.isArray(value);
  }

  /**
   * 检查值是否为非空数组
   * @param value - 要检查的值
   * @returns 是否为非空数组
   */
  static isNonEmptyArray(value: Object): boolean {
    if (!TypeGuards.isArray(value)) {
      return false;
    }
    const arrayValue = value as Array<Object>;
    return arrayValue.length > 0;
  }

  /**
   * 检查值是否为字符串数组
   * @param value - 要检查的值
   * @returns 是否为字符串数组
   */
  static isStringArray(value: Object): boolean {
    if (!TypeGuards.isArray(value)) {
      return false;
    }
    const arrayValue = value as Array<Object>;
    for (let i = 0; i < arrayValue.length; i++) {
      if (!TypeGuards.isString(arrayValue[i])) {
        return false;
      }
    }
    return true;
  }

  /**
   * 检查值是否为数字数组
   * @param value - 要检查的值
   * @returns 是否为数字数组
   */
  static isNumberArray(value: Object): boolean {
    if (!TypeGuards.isArray(value)) {
      return false;
    }
    const arrayValue = value as Array<Object>;
    for (let i = 0; i < arrayValue.length; i++) {
      if (!TypeGuards.isNumber(arrayValue[i])) {
        return false;
      }
    }
    return true;
  }

  /**
   * 检查值是否为对象（非null、非数组）
   * @param value - 要检查的值
   * @returns 是否为对象
   */
  static isObject(value: Object): boolean {  
    return value !== null && typeof value === 'object' && !Array.isArray(value);
  }

  /**
   * 检查值是否为非空对象
   * @param value - 要检查的值
   * @returns 是否为非空对象
   */
  static isNonEmptyObject(value: Object): boolean {
    if (!TypeGuards.isObject(value)) {
      return false;
    }
    const objValue = value as Record<string, Object>;
    return Object.keys(objValue).length > 0;
  }

  /**
   * 检查值是否为null或undefined
   * @param value - 要检查的值
   * @returns 是否为null或undefined
   */
  static isNullOrUndefined(value: Object): boolean {
    return value === null || value === undefined;
  }

  /**
   * 检查值是否为有效的URL
   * @param value - 要检查的值
   * @returns 是否为有效URL
   */
  static isValidUrl(value: Object): boolean {
    if (!TypeGuards.isString(value)) {
      return false;
    }
    
    const urlValue = value as string;
    // 使用正则表达式检查URL格式，替代URL构造函数
    const urlRegex = /^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)$/;
    return urlRegex.test(urlValue);
  }

  /**
   * 检查值是否为有效的邮箱
   * @param value - 要检查的值
   * @returns 是否为有效邮箱
   */
  static isValidEmail(value: Object): boolean {
    if (!TypeGuards.isString(value)) {
      return false;
    }
    
    const emailValue = value as string;
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(emailValue);
  }

  /**
   * 检查值是否为有效的时间戳
   * @param value - 要检查的值
   * @returns 是否为有效时间戳
   */
  static isValidTimestamp(value: Object): boolean {
    if (!TypeGuards.isNumber(value)) {
      return false;
    }
    const numValue = value as number;
    return numValue > 0 && numValue <= Date.now() + 86400000; // 不超过当前时间+1天
  }

  /**
   * 检查值是否为有效的漫画状态
   * @param value - 要检查的值
   * @returns 是否为有效漫画状态
   */
  static isValidMangaStatus(value: Object): boolean {
    if (!TypeGuards.isString(value)) {
      return false;
    }
    const strValue = value as string;
    // 使用显式枚举值检查替代Object.values
    return strValue === MangaStatus.ONGOING || 
           strValue === MangaStatus.COMPLETED || 
           strValue === MangaStatus.HIATUS ||
           strValue === MangaStatus.CANCELLED;
  }

  /**
   * 检查值是否为有效的下载状态
   * @param value - 要检查的值
   * @returns 是否为有效下载状态
   */
  static isValidDownloadStatus(value: Object): boolean {
    if (!TypeGuards.isString(value)) {
      return false;
    }
    const strValue = value as string;
    // 使用显式枚举值检查替代Object.values
    return strValue === DownloadStatus.PENDING || 
           strValue === DownloadStatus.DOWNLOADING || 
           strValue === DownloadStatus.COMPLETED || 
           strValue === DownloadStatus.FAILED || 
           strValue === DownloadStatus.PAUSED;
  }

  /**
   * 检查对象是否包含指定的属性
   * @param obj - 要检查的对象
   * @param properties - 属性名数组
   * @returns 是否包含所有属性
   */
  static hasProperties(obj: Object, properties: Array<string>): boolean {
    if (!TypeGuards.isObject(obj)) {
      return false;
    }
    
    const objValue = obj as Record<string, Object>;
    for (let i = 0; i < properties.length; i++) {
      const prop = properties[i];
      if (!Object.keys(objValue).includes(prop)) {
        return false;
      }
    }
    return true;
  }

  /**
   * 检查对象是否包含指定的必需属性（非null/undefined）
   * @param obj - 要检查的对象
   * @param properties - 属性名数组
   * @returns 是否包含所有必需属性
   */
  static hasRequiredProperties(obj: Object, properties: Array<string>): boolean {
    if (!TypeGuards.isObject(obj)) {
      return false;
    }
    
    const objValue = obj as Record<string, Object>;
    for (let i = 0; i < properties.length; i++) {
      const prop = properties[i];
      if (!Object.keys(objValue).includes(prop)) {
        return false;
      }
      const value = objValue[prop];
      if (value === null || value === undefined) {
        return false;
      }
    }
    return true;
  }

  /**
   * 类型断言辅助函数 - 字符串
   * @param value - 要断言的值
   * @param context - 上下文信息
   * @returns 字符串值
   * @throws 如果类型不匹配
   */
  static assertString(value: Object, context: string = 'value'): string {
    if (!TypeGuards.isString(value)) {
      const error = `${context} 必须是字符串类型，实际类型: ${typeof value}`;
      logger.error(TAG, error);
      throw new Error(error);
    }
    return value as string;
  }

  /**
   * 类型断言辅助函数 - 数字
   * @param value - 要断言的值
   * @param context - 上下文信息
   * @returns 数字值
   * @throws 如果类型不匹配
   */
  static assertNumber(value: Object, context: string = 'value'): number {
    if (!TypeGuards.isNumber(value)) {
      const error = `${context} 必须是数字类型，实际类型: ${typeof value}`;
      logger.error(TAG, error);
      throw new Error(error);
    }
    return value as number;
  }

  /**
   * 类型断言辅助函数 - 布尔值
   * @param value - 要断言的值
   * @param context - 上下文信息
   * @returns 布尔值
   * @throws 如果类型不匹配
   */
  static assertBoolean(value: Object, context: string = 'value'): boolean {
    if (!TypeGuards.isBoolean(value)) {
      const error = `${context} 必须是布尔类型，实际类型: ${typeof value}`;
      logger.error(TAG, error);
      throw new Error(error);
    }
    return value as boolean;
  }

  /**
   * 类型断言辅助函数 - 数组
   * @param value - 要断言的值
   * @param context - 上下文信息
   * @returns 数组值
   * @throws 如果类型不匹配
   */
  static assertArray(value: Object, context: string = 'value'): Array<Object> {
    if (!TypeGuards.isArray(value)) {
      const error = `${context} 必须是数组类型，实际类型: ${typeof value}`;
      logger.error(TAG, error);
      throw new Error(error);
    }
    return value as Array<Object>;
  }

  /**
   * 类型断言辅助函数 - 对象
   * @param value - 要断言的值
   * @param context - 上下文信息
   * @returns 对象值
   * @throws 如果类型不匹配
   */
  static assertObject(value: Object, context: string = 'value'): Record<string, Object> {
    if (!TypeGuards.isObject(value)) {
      const error = `${context} 必须是对象类型，实际类型: ${typeof value}`;
      logger.error(TAG, error);
      throw new Error(error);
    }
    return value as Record<string, Object>;
  }

  /**
   * 安全类型转换 - 带默认值
   * @param value - 要转换的值
   * @param guard - 类型守卫函数
   * @param defaultValue - 默认值
   * @param context - 上下文信息
   * @returns 转换后的值或默认值
   */
  static safeConvert(
    value: Object,
    guard: (val: Object) => boolean,
    defaultValue: Object,
    context: string = 'value'
  ): Object {
    if (guard(value)) {
      return value;
    }
    
    logger.warn(TAG, `${context} 类型检查失败，使用默认值`);
    return defaultValue;
  }

  /**
   * 批量类型检查
   * @param checks - 检查配置数组
   * @returns 所有检查是否通过
   */
  static batchCheck(checks: Array<ITypeCheckConfig>): boolean {
    let allPassed = true;
    
    for (let i = 0; i < checks.length; i++) {
      const check = checks[i];
      if (!check.guard(check.value)) {
        logger.warn(TAG, `类型检查失败: ${check.name}`);
        allPassed = false;
      }
    }
    
    return allPassed;
  }

  /**
   * 安全的字符串转换
   * @param value - 要转换的值
   * @param defaultValue - 默认值
   * @returns 字符串值
   */
  static toSafeString(value: Object, defaultValue: string = ''): string {
    if (TypeGuards.isString(value)) {
      return value as string;
    }
    return defaultValue;
  }

  /**
   * 安全的数字转换
   * @param value - 要转换的值
   * @param defaultValue - 默认值
   * @returns 数字值
   */
  static toSafeNumber(value: Object, defaultValue: number = 0): number {
    if (TypeGuards.isNumber(value)) {
      return value as number;
    }
    return defaultValue;
  }

  /**
   * 安全的布尔值转换
   * @param value - 要转换的值
   * @param defaultValue - 默认值
   * @returns 布尔值
   */
  static toSafeBoolean(value: Object, defaultValue: boolean = false): boolean {
    if (TypeGuards.isBoolean(value)) {
      return value as boolean;
    }
    return defaultValue;
  }

  /**
   * 安全的数组转换
   * @param value - 要转换的值
   * @param defaultValue - 默认值
   * @returns 数组值
   */
  static toSafeArray(value: Object, defaultValue: Array<Object> = []): Array<Object> {
    if (TypeGuards.isArray(value)) {
      return value as Array<Object>;
    }
    return defaultValue;
  }

  /**
   * 安全的对象转换
   * @param value - 要转换的值
   * @param defaultValue - 默认值
   * @returns 对象值
   */
  static toSafeObject(value: Object, defaultValue: Record<string, Object> = {}): Record<string, Object> {
    if (TypeGuards.isObject(value)) {
      return value as Record<string, Object>;
    }
    return defaultValue;
  }
}