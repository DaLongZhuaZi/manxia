// 文件路径: src/main/ets/Framework/Utils/DataValidator.ets
/**
 * 数据验证工具类
 * 提供类型安全的数据验证功能，确保数据的完整性和正确性
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { MangaStatus, DownloadStatus } from 'manxia_core/src/main/ets/Framework/Types/StatusEnums';

const TAG = 'DataValidator';

/**
 * 验证结果接口
 */
export interface ValidationResult {
  isValid: boolean;
  errors: string[];
}

/**
 * 验证规则接口
 */
export interface ValidationRule<T> {
  validate(value: T): ValidationResult;
  message?: string;
}

/**
 * 验证结果实现类
 * 符合ArkTS规范的明确类型定义
 */
class ValidationResultImpl implements ValidationResult {
  isValid: boolean;
  errors: string[];

  constructor(isValid: boolean, errors: string[]) {
    this.isValid = isValid;
    this.errors = errors;
  }
}

/**
 * 验证规则实现类
 * 符合ArkTS规范的明确类型定义
 */
class ValidationRuleImpl<T> implements ValidationRule<T> {
  private validator: (value: T) => boolean;
  message?: string;

  constructor(validator: (value: T) => boolean, message?: string) {
    this.validator = validator;
    this.message = message;
  }

  validate(value: T): ValidationResult {
    const isValid = this.validator(value);
    return new ValidationResultImpl(isValid, isValid ? [] : [this.message || '验证失败']);
  }
}

/**
 * 数据验证工具类
 * 提供类型安全的数据验证功能，确保数据的完整性和正确性
 */
export class DataValidator {

  /**
   * 验证字符串是否非空
   * @param value - 要验证的字符串
   * @param fieldName - 字段名称（用于错误消息）
   * @returns 验证结果
   */
  static validateNonEmptyString(value: string | undefined | null, fieldName: string = 'field'): ValidationResult {
    const errors: string[] = [];
    
    if (value === null || value === undefined) {
      errors.push(`${fieldName} 不能为空`);
    } else if (typeof value !== 'string') {
      errors.push(`${fieldName} 必须是字符串类型`);
    } else if (value.trim().length === 0) {
      errors.push(`${fieldName} 不能为空字符串`);
    }
    
    return new ValidationResultImpl(errors.length === 0, errors);
  }

  /**
   * 验证数字范围
   * @param value - 要验证的数字
   * @param min - 最小值
   * @param max - 最大值
   * @param fieldName - 字段名称
   * @returns 验证结果
   */
  static validateNumberRange(value: number | undefined | null, min: number, max: number, fieldName: string = 'field'): ValidationResult {
    const errors: string[] = [];
    
    if (value === null || value === undefined) {
      errors.push(`${fieldName} 不能为空`);
    } else if (typeof value !== 'number' || isNaN(value)) {
      errors.push(`${fieldName} 必须是有效数字`);
    } else if (value < min) {
      errors.push(`${fieldName} 不能小于 ${min}`);
    } else if (value > max) {
      errors.push(`${fieldName} 不能大于 ${max}`);
    }
    
    return new ValidationResultImpl(errors.length === 0, errors);
  }

  /**
   * 验证URL格式
   * @param value - 要验证的URL
   * @param fieldName - 字段名称
   * @returns 验证结果
   */
  static validateUrl(value: string | undefined | null, fieldName: string = 'URL'): ValidationResult {
    const errors: string[] = [];
    
    if (value === null || value === undefined) {
      errors.push(`${fieldName} 不能为空`);
    } else if (typeof value !== 'string') {
      errors.push(`${fieldName} 必须是字符串类型`);
    } else {
      // 修复：使用正则表达式替代URL构造函数，因为ArkTS不支持URL构造函数
      const urlRegex = /^https?:\/\/(?:[-\w.])+(?:\:[0-9]+)?(?:\/(?:[\w\/_.])*(?:\?(?:[\w&=%.])*)?(?:\#(?:[\w.])*)?)?$/;
      if (!urlRegex.test(value)) {
        errors.push(`${fieldName} 格式无效`);
      }
    }
    
    return new ValidationResultImpl(errors.length === 0, errors);
  }

  /**
   * 验证邮箱格式
   * @param value - 要验证的邮箱
   * @param fieldName - 字段名称
   * @returns 验证结果
   */
  static validateEmail(value: string | undefined | null, fieldName: string = 'email'): ValidationResult {
    const errors: string[] = [];
    
    if (value === null || value === undefined) {
      errors.push(`${fieldName} 不能为空`);
    } else if (typeof value !== 'string') {
      errors.push(`${fieldName} 必须是字符串类型`);
    } else {
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!emailRegex.test(value)) {
        errors.push(`${fieldName} 格式无效`);
      }
    }
    
    return new ValidationResultImpl(errors.length === 0, errors);
  }

  /**
   * 验证数组是否非空
   * @param value - 要验证的数组
   * @param fieldName - 字段名称
   * @returns 验证结果
   */
  static validateNonEmptyArray<T>(value: T[] | undefined | null, fieldName: string = 'array'): ValidationResult {
    const errors: string[] = [];
    
    if (value === null || value === undefined) {
      errors.push(`${fieldName} 不能为空`);
    } else if (!Array.isArray(value)) {
      errors.push(`${fieldName} 必须是数组类型`);
    } else if (value.length === 0) {
      errors.push(`${fieldName} 不能为空数组`);
    }
    
    return new ValidationResultImpl(errors.length === 0, errors);
  }

  /**
   * 验证漫画状态
   * @param value - 要验证的状态
   * @param fieldName - 字段名称
   * @returns 验证结果
   */
  static validateMangaStatus(value: string | undefined | null, fieldName: string = 'status'): ValidationResult {
    const errors: string[] = [];
    
    if (value === null || value === undefined) {
      errors.push(`${fieldName} 不能为空`);
    } else if (typeof value !== 'string') {
      errors.push(`${fieldName} 必须是字符串类型`);
    } else {
      const validStatuses = Object.values(MangaStatus);
      if (!validStatuses.includes(value as MangaStatus)) {
        errors.push(`${fieldName} 必须是有效的漫画状态: ${validStatuses.join(', ')}`);
      }
    }
    
    return new ValidationResultImpl(errors.length === 0, errors);
  }

  /**
   * 验证下载状态
   * @param value - 要验证的状态
   * @param fieldName - 字段名称
   * @returns 验证结果
   */
  static validateDownloadStatus(value: string | undefined | null, fieldName: string = 'downloadStatus'): ValidationResult {
    const errors: string[] = [];
    
    if (value === null || value === undefined) {
      errors.push(`${fieldName} 不能为空`);
    } else if (typeof value !== 'string') {
      errors.push(`${fieldName} 必须是字符串类型`);
    } else {
      const validStatuses = Object.values(DownloadStatus);
      if (!validStatuses.includes(value as DownloadStatus)) {
        errors.push(`${fieldName} 必须是有效的下载状态: ${validStatuses.join(', ')}`);
      }
    }
    
    return new ValidationResultImpl(errors.length === 0, errors);
  }

  /**
   * 验证时间戳
   * @param value - 要验证的时间戳
   * @param fieldName - 字段名称
   * @returns 验证结果
   */
  static validateTimestamp(value: number | undefined | null, fieldName: string = 'timestamp'): ValidationResult {
    const errors: string[] = [];
    
    if (value === null || value === undefined) {
      errors.push(`${fieldName} 不能为空`);
    } else if (typeof value !== 'number' || isNaN(value)) {
      errors.push(`${fieldName} 必须是有效数字`);
    } else if (value < 0) {
      errors.push(`${fieldName} 不能为负数`);
    } else if (value > Date.now() + 86400000) { // 不能超过当前时间+1天
      errors.push(`${fieldName} 不能是未来时间`);
    }
    
    return new ValidationResultImpl(errors.length === 0, errors);
  }

  /**
   * 验证对象是否包含必需字段
   * @param obj - 要验证的对象
   * @param requiredFields - 必需字段列表
   * @param objectName - 对象名称
   * @returns 验证结果
   */
  static validateRequiredFields(obj: Record<string, Object> | undefined | null, requiredFields: string[], objectName: string = 'object'): ValidationResult {
    const errors: string[] = [];
    
    if (obj === null || obj === undefined) {
      errors.push(`${objectName} 不能为空`);
      return new ValidationResultImpl(false, errors);
    }
    
    if (typeof obj !== 'object') {
      errors.push(`${objectName} 必须是对象类型`);
      return new ValidationResultImpl(false, errors);
    }
    
    const objRecord = obj as Record<string, Object>;
    for (const field of requiredFields) {
      // 修复：使用Object.keys().includes()替代in操作符，符合ArkTS规范
      const objKeys = Object.keys(objRecord);
      if (!objKeys.includes(field) || objRecord[field] === null || objRecord[field] === undefined) {
        errors.push(`${objectName} 缺少必需字段: ${field}`);
      }
    }
    
    return new ValidationResultImpl(errors.length === 0, errors);
  }

  /**
   * 组合多个验证结果
   * @param results - 验证结果数组
   * @returns 合并后的验证结果
   */
  static combineResults(results: ValidationResult[]): ValidationResult {
    const allErrors: string[] = [];
    let isValid = true;
    
    for (const result of results) {
      if (!result.isValid) {
        isValid = false;
        allErrors.push(...result.errors);
      }
    }
    
    return new ValidationResultImpl(isValid, allErrors);
  }

  /**
   * 创建自定义验证规则
   * @param validator - 验证函数
   * @param message - 错误消息
   * @returns 验证规则
   */
  static createRule<T>(validator: (value: T) => boolean, message: string): ValidationRule<T> {
    return new ValidationRuleImpl<T>(validator, message);
  }

  /**
   * 应用验证规则
   * @param value - 要验证的值
   * @param rules - 验证规则数组
   * @returns 验证结果
   */
  static applyRules<T>(value: T, rules: ValidationRule<T>[]): ValidationResult {
    const results = rules.map(rule => rule.validate(value));
    return DataValidator.combineResults(results);
  }

  /**
   * 记录验证错误
   * @param result - 验证结果
   * @param context - 上下文信息
   */
  static logValidationErrors(result: ValidationResult, context: string = ''): void {
    if (!result.isValid) {
      const contextMsg = context ? `[${context}] ` : '';
      logger.warn(TAG, `${contextMsg}验证失败: ${result.errors.join(', ')}`);
    }
  }
}