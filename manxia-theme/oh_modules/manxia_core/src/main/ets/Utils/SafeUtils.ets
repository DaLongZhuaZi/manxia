import { logger } from './Logger';

const TAG = 'SafeUtils';

export class SafeUtils {
  /**
   * 安全解析JSON字符串为对象。解析失败返回空对象 {}。
   */
  static parseObj<T>(jsonStr: string | undefined | null): T {
    let emptyObj: Record<string, Object> = {};
    if (!jsonStr || jsonStr.trim() === '') {
      return emptyObj as T;
    }
    try {
      return JSON.parse(jsonStr) as T;
    } catch (error) {
      logger.error(TAG, `JSON parse error (Obj): ${String(error)}, prefix: ${jsonStr.substring(0, 100)}`);
      return emptyObj as T;
    }
  }

  /**
   * 安全解析JSON字符串为数组。解析失败返回空数组 []。
   */
  static parseArr<T>(jsonStr: string | undefined | null): T {
    if (!jsonStr || jsonStr.trim() === '') {
      return [] as T;
    }
    try {
      return JSON.parse(jsonStr) as T;
    } catch (error) {
      logger.error(TAG, `JSON parse error (Arr): ${String(error)}, prefix: ${jsonStr.substring(0, 100)}`);
      return [] as T;
    }
  }

  /**
   * 安全解析JSON字符串为字符串。解析失败返回空字符串 ""。
   */
  static parseStr(jsonStr: string | undefined | null): string {
    if (!jsonStr || jsonStr.trim() === '') {
      return '';
    }
    try {
      return JSON.parse(jsonStr) as string;
    } catch (error) {
      logger.error(TAG, `JSON parse error (Str): ${String(error)}, prefix: ${jsonStr.substring(0, 100)}`);
      return '';
    }
  }

  /**
   * 安全解析JSON字符串为数字。解析失败返回 0。
   */
  static parseNum(jsonStr: string | undefined | null): number {
    if (!jsonStr || jsonStr.trim() === '') {
      return 0;
    }
    try {
      return JSON.parse(jsonStr) as number;
    } catch (error) {
      logger.error(TAG, `JSON parse error (Num): ${String(error)}, prefix: ${jsonStr.substring(0, 100)}`);
      return 0;
    }
  }

  /**
   * 安全解析JSON字符串为布尔值。解析失败返回 false。
   */
  static parseBool(jsonStr: string | undefined | null): boolean {
    if (!jsonStr || jsonStr.trim() === '') {
      return false;
    }
    try {
      return JSON.parse(jsonStr) as boolean;
    } catch (error) {
      logger.error(TAG, `JSON parse error (Bool): ${String(error)}, prefix: ${jsonStr.substring(0, 100)}`);
      return false;
    }
  }

  /**
   * 当确定无法提供合适的 fallback 时，可以使用这个变体，它允许返回 undefined
   */
  static parseOptional<T>(jsonStr: string | undefined | null): T | undefined {
    if (!jsonStr || jsonStr.trim() === '') {
      return undefined;
    }
    try {
      return JSON.parse(jsonStr) as T;
    } catch (error) {
      logger.error(TAG, `JSON parse error (Optional): ${String(error)}, prefix: ${jsonStr.substring(0, 100)}`);
      return undefined;
    }
  }

  /**
   * 安全地序列化对象为JSON字符串。
   */
  static stringifyJson(obj: Object | undefined | null, fallback: string = ''): string {
    if (obj === undefined || obj === null) return fallback;
    try {
      return JSON.stringify(obj);
    } catch (error) {
      logger.error(TAG, `JSON stringify error: ${String(error)}`);
      return fallback;
    }
  }
}
