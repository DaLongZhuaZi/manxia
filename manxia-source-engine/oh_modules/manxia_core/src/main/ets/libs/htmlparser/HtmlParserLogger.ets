/**
 * HTML 解析器日志模块
 * 集成系统自定义日志系统，提供统一的日志接口
 */

import { logger } from '../../Utils/Logger';

const TAG = 'HtmlParser';

/**
 * HTML 解析器日志类
 * 提供解析器专用的日志方法
 */
export class HtmlParserLogger {
  private static _enabled: boolean = true;
  private static _debugEnabled: boolean = false;

  /**
   * 启用/禁用日志
   */
  static setEnabled(enabled: boolean): void {
    HtmlParserLogger._enabled = enabled;
  }

  /**
   * 启用/禁用调试日志
   */
  static setDebugEnabled(enabled: boolean): void {
    HtmlParserLogger._debugEnabled = enabled;
  }

  /**
   * 是否启用日志
   */
  static isEnabled(): boolean {
    return HtmlParserLogger._enabled;
  }

  /**
   * 调试日志
   */
  static debug(message: string): void {
    if (HtmlParserLogger._enabled && HtmlParserLogger._debugEnabled) {
      logger.debug(TAG, message);
    }
  }

  /**
   * 信息日志
   */
  static info(message: string): void {
    if (HtmlParserLogger._enabled) {
      logger.info(TAG, message);
    }
  }

  /**
   * 警告日志
   */
  static warn(message: string): void {
    if (HtmlParserLogger._enabled) {
      logger.warn(TAG, message);
    }
  }

  /**
   * 错误日志
   */
  static error(message: string): void {
    if (HtmlParserLogger._enabled) {
      logger.error(TAG, message);
    }
  }

  /**
   * 解析开始日志
   */
  static parseStart(htmlLength: number): void {
    if (HtmlParserLogger._enabled && HtmlParserLogger._debugEnabled) {
      logger.debug(TAG, `开始解析 HTML，长度: ${htmlLength} 字符`);
    }
  }

  /**
   * 解析完成日志
   */
  static parseComplete(elementCount: number, duration: number): void {
    if (HtmlParserLogger._enabled && HtmlParserLogger._debugEnabled) {
      logger.debug(TAG, `解析完成，元素数: ${elementCount}，耗时: ${duration}ms`);
    }
  }

  /**
   * 选择器查询日志
   */
  static selectorQuery(selector: string, resultCount: number): void {
    if (HtmlParserLogger._enabled && HtmlParserLogger._debugEnabled) {
      logger.debug(TAG, `选择器查询: "${selector}"，结果数: ${resultCount}`);
    }
  }

  /**
   * 解析错误日志
   */
  static parseError(position: number, message: string): void {
    if (HtmlParserLogger._enabled) {
      logger.warn(TAG, `解析警告 (位置 ${position}): ${message}`);
    }
  }
}
