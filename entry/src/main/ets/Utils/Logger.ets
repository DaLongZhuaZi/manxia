// 文件路径: src/main/ets/Utils/Logger.ts
/**
 * 日志系统模块
 * 提供应用级别的日志记录功能，支持不同级别的日志输出
 * 包括调试、信息、警告和错误日志
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { logCollector } from '../Framework/Debug/LogCollector';
import { TimeUtils } from '../Framework/Utils/TimeUtils';

// 在模块加载时立即启用日志收集
logCollector.setEnabled(true);
console.log('[NGF] Logger模块已加载，日志收集已启用');

const Flag = 'wwssadad';

/**
 * 🎮 边缘世界框架 - 日志系统
 * 定义日志的级别
 * DEBUG: 🔍 用于开发过程中的调试信息
 * INFO: ℹ️ 用于记录应用运行的关键信息
 * WARN: ⚠️ 用于记录潜在的问题或非致命错误
 * ERROR: ❌ 用于记录导致功能失败的错误
 */
export enum LogLevel {
  DEBUG,
  INFO,
  WARN,
  ERROR
}

// 🏷️ 默认的日志输出领域（Domain），一般固定为应用的一个标识
const LOG_DOMAIN = 0x0000;

// 🎨 日志级别对应的中文标识和特殊符号
export const LOG_LEVEL_SYMBOLS: Record<LogLevel, string> = {
  0: '🔍 调试',  // LogLevel.DEBUG
  1: 'ℹ️ 信息',  // LogLevel.INFO
  2: '⚠️ 警告',  // LogLevel.WARN
  3: '❌ 错误'   // LogLevel.ERROR
};

// 🏷️ 常用标签的中文映射
const TAG_MAPPING: Record<string, string> = {
  'GameFramework': '🎮 游戏框架',
  'EntryAbility': '🚀 应用入口',
  'EntryBackupAbility': '💾 备份恢复',
  'GlobalContext': '🌐 全局上下文',
  'Engine': '⚙️ 游戏引擎',
  'EntityManager': '👥 实体管理器',
  'ComponentManager': '🧩 组件管理器',
  'SystemManager': '🔧 系统管理器',
  'SceneManager': '🎬 场景管理器',
  'DataManager': '📊 数据管理器',
  'RenderSystem': '🎨 渲染系统',
  'GameView': '🖼️ 游戏视图',
  'Index': '🏠 主页面',
  'MainMenuScene': '📋 主菜单场景',
  'GameWorldScene': '🌍 游戏世界场景'
};

class Logger {
  private static instance: Logger;
  
  // 当前的日志输出级别，只有高于或等于此级别的日志才会被打印
  // 您可以在应用启动时根据环境（开发/生产）来设置它
  private currentLevel: LogLevel = LogLevel.DEBUG;
  
  // 是否启用时间戳
  private enableTimestamp: boolean = true;

  /**
   * 获取Logger单例实例
   */
  public static getInstance(): Logger {
    if (!Logger.instance) {
      Logger.instance = new Logger();
    }
    return Logger.instance;
  }

  /**
   * 设置日志系统的输出级别
   * @param level - 您想显示的最低日志级别
   * @example
   * // 在生产环境中，只显示警告和错误
   * Logger.setLevel(LogLevel.WARN);
   */
  public setLevel(level: LogLevel): void {
    this.currentLevel = level;
  }
  
  /**
   * 设置是否在日志中显示时间戳
   * @param enable - 是否启用时间戳
   */
  public setEnableTimestamp(enable: boolean): void {
    this.enableTimestamp = enable;
  }
  
  /**
   * 获取格式化的时间戳
   * @returns 格式化的时间戳字符串
   */
  private getTimestamp(): string {
    return TimeUtils.formatTimestamp(Date.now(), 'HH:mm:ss.SSS');
  }
  
  /**
   * 格式化日志消息
   * @param level - 日志级别
   * @param tag - 日志标签
   * @param message - 日志消息
   * @returns 格式化后的日志消息
   */
  private formatMessage(level: LogLevel, tag: string, message: string): string {
    // [新增] 定义您需要的全局日志前缀
    const globalPrefix = '[NGF] ';
    const levelSymbol = LOG_LEVEL_SYMBOLS[level];
    const chineseTag = TAG_MAPPING[tag] || tag;
    const timestamp = this.enableTimestamp ? this.getTimestamp() + ' ' : '';
    const formattedMessage = `${globalPrefix}${timestamp}${levelSymbol} [${chineseTag}] ${message}`;
    // 确保所有日志都被收集，即使在早期启动阶段
    if (!logCollector.isCollectorEnabled()) {
      logCollector.setEnabled(true);
    }
    return formattedMessage;
  }

  /**
   * 🔍 调试级别的日志
   * @param tag - 日志分类标签, 例如 'RenderSystem'
   * @param message - 要输出的日志信息
   * @param args - 其他可选参数
   */
  public debug(tag: string, message: string, ...args: (string | number | boolean)[]): void {
    if (this.currentLevel <= LogLevel.DEBUG) {
      const formattedMessage = this.formatMessage(LogLevel.DEBUG, tag, message);
      hilog.debug(LOG_DOMAIN, Flag, `%{public}s`, formattedMessage);
      // 同时发送到日志收集器
      logCollector.addLog(LogLevel.DEBUG, tag, message, args);
    }
  }

  /**
   * ℹ️ 信息级别的日志
   * @param tag - 日志分类标签
   * @param message - 要输出的日志信息
   * @param args - 其他可选参数
   */
  public info(tag: string, message: string, ...args: (string | number | boolean)[]): void {
    if (this.currentLevel <= LogLevel.INFO) {
      const formattedMessage = this.formatMessage(LogLevel.INFO, tag, message);
      hilog.info(LOG_DOMAIN, Flag, `%{public}s`, formattedMessage);
      // 同时发送到日志收集器
      logCollector.addLog(LogLevel.INFO, tag, message, args);
    }
  }

  /**
   * ⚠️ 警告级别的日志
   * @param tag - 日志分类标签
   * @param message - 要输出的日志信息
   * @param args - 其他可选参数
   */
  public warn(tag: string, message: string, ...args: (string | number | boolean)[]): void {
    if (this.currentLevel <= LogLevel.WARN) {
      const formattedMessage = this.formatMessage(LogLevel.WARN, tag, message);
      hilog.warn(LOG_DOMAIN, Flag, `%{public}s`, formattedMessage);
      // 同时发送到日志收集器
      logCollector.addLog(LogLevel.WARN, tag, message, args);
    }
  }

  /**
   * ❌ 错误级别的日志
   * @param tag - 日志分类标签
   * @param message - 要输出的日志信息
   * @param args - 其他可选参数
   */
  public error(tag: string, message: string, ...args: (string | number | boolean)[]): void {
    if (this.currentLevel <= LogLevel.ERROR) {
      const formattedMessage = this.formatMessage(LogLevel.ERROR, tag, message);
      hilog.error(LOG_DOMAIN, Flag, `%{public}s`, formattedMessage);
      // 同时发送到日志收集器
      logCollector.addLog(LogLevel.ERROR, tag, message, args);
    }
  }
  
  /**
   * 📝 记录应用生命周期事件
   * @param tag - 日志分类标签
   * @param event - 生命周期事件名称
   * @param details - 事件详情
   */
  public lifecycle(tag: string, event: string, details?: string): void {
    const detailsText = details ? ` - ${details}` : '';
    this.info(tag, `🔄 生命周期事件: ${event}${detailsText}`);
  }
  
  /**
   * 🚀 记录应用启动过程
   * @param tag - 日志分类标签
   * @param step - 启动步骤
   * @param details - 步骤详情
   */
  public startup(tag: string, step: string, details?: string): void {
    const detailsText = details ? ` - ${details}` : '';
    this.info(tag, `🚀 启动过程: ${step}${detailsText}`);
  }
  
  /**
   * 🔄 记录状态变化
   * @param tag - 日志分类标签
   * @param from - 原状态
   * @param to - 新状态
   * @param details - 变化详情
   */
  public stateChange(tag: string, from: string, to: string, details?: string): void {
    const detailsText = details ? ` - ${details}` : '';
    this.info(tag, `🔄 状态变化: ${from} → ${to}${detailsText}`);
  }
  
  /**
   * 📊 记录性能相关信息
   * @param tag - 日志分类标签
   * @param metric - 性能指标名称
   * @param value - 性能指标值
   * @param unit - 单位
   */
  public performance(tag: string, metric: string, value: number, unit: string): void {
    this.debug(tag, `📊 性能指标: ${metric} = ${value}${unit}`);
  }
}

// 导出一个Logger的单例，方便在全局任何地方使用
export const logger = Logger.getInstance();
