import { SafeUtils } from '../../Utils/SafeUtils';
// 文件路径: src/main/ets/Framework/Utils/DataConverter.ets
/**
 * 数据转换工具类
 * 提供类型安全的数据转换功能，确保数据在不同格式间的正确转换
 */

import { logger } from '../../Utils/Logger';
import { TimeUtils } from './TimeUtils';
import { MangaStatus, DownloadStatus } from '../Types/StatusEnums';

const TAG = 'DataConverter';

/**
 * 清理后的对象接口 - 修复：使用Record类型替代索引签名
 */
type CleanedObject = Record<string, Object>;

/**
 * 合并对象的结果接口 - 修复：使用正确的类型定义
 */
type MergedObjectResult<T extends Record<string, Object>> = T;

/**
 * 数据转换工具类
 * 提供类型安全的数据转换功能，确保数据在不同格式间的正确转换
 * 转换状态字符串为MangaStatus枚举
 * @param status - 状态字符串
 * @returns MangaStatus枚举值
 */
export class DataConverter {
  static toMangaStatus(status: string | undefined | null): MangaStatus {
    if (!status) {
      logger.warn(TAG, '状态值为空，使用默认值 ongoing');
      return MangaStatus.ONGOING;
    }

    const normalizedStatus = status.toLowerCase().trim();
    switch (normalizedStatus) {
      case 'ongoing':
        return MangaStatus.ONGOING;
      case 'completed':
        return MangaStatus.COMPLETED;
      case 'paused':
      case 'hiatus':
        return MangaStatus.HIATUS; // 修复：使用HIATUS替代PAUSED
      default:
        logger.warn(TAG, `未知的漫画状态: ${status}，使用默认值 ongoing`);
        return MangaStatus.ONGOING;
    }
  }

  /**
   * 转换状态字符串为DownloadStatus枚举
   * @param status - 状态字符串
   * @returns DownloadStatus枚举值
   */
  static toDownloadStatus(status: string | undefined | null): DownloadStatus {
    if (!status) {
      logger.warn(TAG, '下载状态值为空，使用默认值 pending');
      return DownloadStatus.PENDING;
    }

    const normalizedStatus = status.toLowerCase().trim();
    switch (normalizedStatus) {
      case 'pending':
        return DownloadStatus.PENDING;
      case 'downloading':
        return DownloadStatus.DOWNLOADING;
      case 'completed':
        return DownloadStatus.COMPLETED;
      case 'failed':
        return DownloadStatus.FAILED;
      case 'paused':
        return DownloadStatus.PAUSED;
      default:
        logger.warn(TAG, `未知的下载状态: ${status}，使用默认值 pending`);
        return DownloadStatus.PENDING;
    }
  }

  /**
   * 转换时间值为时间戳
   * @param timeValue - 时间值（可能是Date、string、number或null/undefined）
   * @returns 时间戳（毫秒）
   */
  static toTimestamp(timeValue: Date | string | number | undefined | null): number {
    if (timeValue === null || timeValue === undefined) {
      logger.warn(TAG, '时间值为空，使用当前时间');
      return Date.now();
    }

    try {
      return TimeUtils.toTimestamp(timeValue);
    } catch (error) {
      logger.error(TAG, `时间转换失败: ${error}，使用当前时间`);
      return Date.now();
    }
  }

  /**
   * 安全转换字符串
   * @param value - 输入值
   * @param defaultValue - 默认值
   * @returns 字符串值
   */
  static toString(value: Object, defaultValue: string = ''): string {
    if (value === null || value === undefined) {
      return defaultValue;
    }
    
    if (typeof value === 'string') {
      return value;
    }
    
    try {
      return String(value);
    } catch (error) {
      logger.warn(TAG, `字符串转换失败: ${error}，使用默认值`);
      return defaultValue;
    }
  }

  /**
   * 安全转换数字
   * @param value - 输入值
   * @param defaultValue - 默认值
   * @returns 数字值
   */
  static toNumber(value: Object, defaultValue: number = 0): number {
    if (value === null || value === undefined) {
      return defaultValue;
    }
    
    if (typeof value === 'number' && !isNaN(value)) {
      return value;
    }
    
    if (typeof value === 'string') {
      const parsed = parseFloat(value);
      if (!isNaN(parsed)) {
        return parsed;
      }
    }
    
    logger.warn(TAG, `数字转换失败: ${value}，使用默认值 ${defaultValue}`);
    return defaultValue;
  }

  /**
   * 安全转换整数
   * @param value - 输入值
   * @param defaultValue - 默认值
   * @returns 整数值
   */
  static toInteger(value: Object, defaultValue: number = 0): number {
    const num = DataConverter.toNumber(value, defaultValue);
    return Math.floor(num);
  }

  /**
   * 安全转换布尔值
   * @param value - 输入值
   * @param defaultValue - 默认值
   * @returns 布尔值
   */
  static toBoolean(value: Object, defaultValue: boolean = false): boolean {
    if (value === null || value === undefined) {
      return defaultValue;
    }
    
    if (typeof value === 'boolean') {
      return value;
    }
    
    if (typeof value === 'string') {
      const normalized = value.toLowerCase().trim();
      if (normalized === 'true' || normalized === '1' || normalized === 'yes') {
        return true;
      }
      if (normalized === 'false' || normalized === '0' || normalized === 'no') {
        return false;
      }
    }
    
    if (typeof value === 'number') {
      return value !== 0;
    }
    
    logger.warn(TAG, `布尔值转换失败: ${value}，使用默认值 ${defaultValue}`);
    return defaultValue;
  }

  /**
   * 安全转换数组
   * @param value - 输入值
   * @param defaultValue - 默认值
   * @returns 数组值
   */
  static toArray<T>(value: Object, defaultValue: T[] = []): T[] {
    if (value === null || value === undefined) {
      return defaultValue;
    }
    
    if (Array.isArray(value)) {
      return value as T[];
    }
    
    logger.warn(TAG, `数组转换失败: ${typeof value}，使用默认值`);
    return defaultValue;
  }

  /**
   * 深度克隆对象
   * @param obj - 要克隆的对象
   * @returns 克隆后的对象
   */
  static deepClone<T>(obj: T): T {
    if (obj === null || typeof obj !== 'object') {
      return obj;
    }
    
    try {
      return SafeUtils.parseObj(JSON.stringify(obj));
    } catch (error) {
      logger.error(TAG, `深度克隆失败: ${error}`);
      return obj;
    }
  }

  /**
   * 合并对象属性
   * @param target - 目标对象
   * @param source - 源对象
   * @returns 合并后的对象
   */
  static mergeObjects<T extends Record<string, Object>>(target: T, source: T): T {
    const result = DataConverter.deepClone(target);
    
    // 修复：使用显式属性访问替代动态键访问，消除any/unknown类型推断
    const sourceKeys = Object.keys(source);
    for (let i = 0; i < sourceKeys.length; i++) {
      const key = sourceKeys[i];
      // 修复：使用类型断言确保类型安全
      const sourceRecord = source as Record<string, Object>;
      const sourceValue = sourceRecord[key];
      if (sourceValue !== undefined) {
        const resultRecord = result as Record<string, Object>;
        resultRecord[key] = sourceValue;
      }
    }
    
    return result;
  }

  /**
   * 清理对象中的空值
   * @param obj - 输入对象
   * @returns 清理后的对象
   */
  static cleanObject<T extends Record<string, Object>>(obj: T): CleanedObject {
    // 修复：使用CleanedObject类型作为返回类型
    const result: CleanedObject = {};
    
    // 修复：使用传统循环替代for...of，消除索引访问问题
    const objKeys = Object.keys(obj);
    for (let i = 0; i < objKeys.length; i++) {
      const key = objKeys[i];
      // 修复：使用类型断言确保类型安全，消除any/unknown类型推断
      const objRecord = obj as Record<string, Object>;
      const value = objRecord[key];
      if (value !== null && value !== undefined && value !== '') {
        result[key] = value;
      }
    }
    
    return result;
  }
}