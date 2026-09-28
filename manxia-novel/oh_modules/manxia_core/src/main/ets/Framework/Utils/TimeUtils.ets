// 文件路径: src/main/ets/Framework/Utils/TimeUtils.ets
/**
 * 时间工具类
 * 统一处理项目中的时间格式，标准化为number类型时间戳
 */

import { logger } from '../../Utils/Logger';

const TAG = 'TimeUtils';

export interface TimeConstants {
  /** 秒级时间戳 */
  SECOND: number;
  /** 分钟级时间戳 */
  MINUTE: number;
  /** 小时级时间戳 */
  HOUR: number;
  /** 天级时间戳 */
  DAY: number;
  /** 周级时间戳 */
  WEEK: number;
  /** 月级时间戳 */
  MONTH: number;
  /** 年级时间戳 */
  YEAR: number;
}


/**
 * 时间工具类
 * 提供统一的时间处理方法，确保项目中时间格式的一致性
 */
export class TimeUtils {
  /**
   * 将各种时间格式转换为时间戳
   * @param input - 输入的时间值（Date对象、ISO字符串或时间戳）
   * @returns 时间戳（毫秒）
   */
  static toTimestamp(input: Date | string | number | undefined): number {
    if (input === undefined || input === null) {
      return Date.now();
    }

    if (typeof input === 'number') {
      // 如果是秒级时间戳，转换为毫秒
      return input < 10000000000 ? input * 1000 : input;
    }

    if (typeof input === 'string') {
      const parsed = Date.parse(input);
      if (isNaN(parsed)) {
        logger.warn(TAG, `无效的时间字符串: ${input}，使用当前时间`);
        return Date.now();
      }
      return parsed;
    }

    if (input instanceof Date) {
      const timestamp = input.getTime();
      if (isNaN(timestamp)) {
        logger.warn(TAG, `无效的Date对象，使用当前时间`);
        return Date.now();
      }
      return timestamp;
    }

    logger.warn(TAG, `未知的时间格式: ${typeof input}，使用当前时间`);
    return Date.now();
  }

  /**
   * 将时间戳转换为Date对象
   * @param timestamp - 时间戳（毫秒）
   * @returns Date对象
   */
  static toDate(timestamp: number): Date {
    return new Date(timestamp);
  }

  /**
   * 将时间戳转换为ISO字符串
   * @param timestamp - 时间戳（毫秒）
   * @returns ISO格式的时间字符串
   */
  static toISOString(timestamp: number): string {
    return new Date(timestamp).toISOString();
  }

  /**
   * 格式化时间戳为显示字符串
   * @param timestamp - 时间戳（毫秒）
   * @param format - 格式类型
   * @returns 格式化的时间字符串
   */
  static formatDisplay(timestamp: number, format: 'date' | 'datetime' | 'time' | 'relative' = 'datetime'): string {
    const date = new Date(timestamp);
    
    switch (format) {
      case 'date':
        return date.toLocaleDateString('zh-CN');
      case 'time':
        return date.toLocaleTimeString('zh-CN');
      case 'datetime':
        return date.toLocaleString('zh-CN');
      case 'relative':
        return TimeUtils.getRelativeTime(timestamp);
      default:
        return date.toLocaleString('zh-CN');
    }
  }

  /**
   * 格式化时间戳为自定义格式字符串
   * @param timestamp - 时间戳（毫秒）
   * @param pattern - 格式模式（如 'HH:mm:ss.SSS'）
   * @returns 格式化的时间字符串
   */
  static formatTimestamp(timestamp: number, pattern: string): string {
    const date = new Date(timestamp);
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    const seconds = date.getSeconds().toString().padStart(2, '0');
    const milliseconds = date.getMilliseconds().toString().padStart(3, '0');
    
    return `[${hours}:${minutes}:${seconds}.${milliseconds}]`;
  }

  /**
   * 获取相对时间描述
   * @param timestamp - 时间戳（毫秒）
   * @returns 相对时间字符串（如：刚刚、5分钟前、2小时前等）
   */
  static getRelativeTime(timestamp: number): string {
    const now = Date.now();
    const diff = now - timestamp;
    
    if (diff < 0) {
      return '未来时间';
    }

    const seconds = Math.floor(diff / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);
    const months = Math.floor(days / 30);
    const years = Math.floor(days / 365);

    if (seconds < 60) {
      return '刚刚';
    } else if (minutes < 60) {
      return `${minutes}分钟前`;
    } else if (hours < 24) {
      return `${hours}小时前`;
    } else if (days < 30) {
      return `${days}天前`;
    } else if (months < 12) {
      return `${months}个月前`;
    } else {
      return `${years}年前`;
    }
  }

  /**
   * 验证时间戳是否有效
   * @param timestamp - 时间戳
   * @returns 是否有效
   */
  static isValidTimestamp(timestamp: number): boolean {
    return !isNaN(timestamp) && timestamp > 0 && timestamp <= Date.now() + 86400000; // 允许未来24小时内的时间
  }

  /**
   * 获取当前时间戳
   * @returns 当前时间戳（毫秒）
   */
  static now(): number {
    return Date.now();
  }

  /**
   * 计算两个时间戳之间的差值
   * @param start - 开始时间戳
   * @param end - 结束时间戳（默认为当前时间）
   * @returns 时间差（毫秒）
   */
  static diff(start: number, end: number = Date.now()): number {
    return end - start;
  }

  /**
   * 格式化持续时间
   * @param duration - 持续时间（毫秒）
   * @returns 格式化的持续时间字符串
   */
  static formatDuration(duration: number): string {
    const seconds = Math.floor(duration / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);

    if (days > 0) {
      return `${days}天${hours % 24}小时`;
    } else if (hours > 0) {
      return `${hours}小时${minutes % 60}分钟`;
    } else if (minutes > 0) {
      return `${minutes}分钟${seconds % 60}秒`;
    } else {
      return `${seconds}秒`;
    }
  }
}

/**
 * 时间相关的常量
 */
export const TIME_CONSTANTS: TimeConstants = {
  /** 一秒的毫秒数 */
  SECOND: 1000,
  /** 一分钟的毫秒数 */
  MINUTE: 60 * 1000,
  /** 一小时的毫秒数 */
  HOUR: 60 * 60 * 1000,
  /** 一天的毫秒数 */
  DAY: 24 * 60 * 60 * 1000,
  /** 一周的毫秒数 */
  WEEK: 7 * 24 * 60 * 60 * 1000,
  /** 一个月的毫秒数（30天） */
  MONTH: 30 * 24 * 60 * 60 * 1000,
  /** 一年的毫秒数（365天） */
  YEAR: 365 * 24 * 60 * 60 * 1000
};