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
  OFF = -1,  // 关闭所有日志输出
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
  FATAL = 4
}

// 🏷️ 默认的日志输出领域（Domain），一般固定为应用的一个标识
const LOG_DOMAIN = 0x0000;

// 🎨 日志级别对应的中文标识和特殊符号
export const LOG_LEVEL_SYMBOLS: Map<number, string> = new Map<number, string>([
  [LogLevel.OFF, '🚫 关闭'],
  [LogLevel.DEBUG, '🔍 调试'],
  [LogLevel.INFO, 'ℹ️ 信息'],
  [LogLevel.WARN, '⚠️ 警告'],
  [LogLevel.ERROR, '❌ 错误'],
  [LogLevel.FATAL, '💀 致命']
]);

// 日志级别名称映射（用于设置界面显示）
export const LOG_LEVEL_NAMES: string[] = ['关闭', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'];

// 日志级别值映射（从名称索引到LogLevel值）
export const LOG_LEVEL_VALUES: LogLevel[] = [LogLevel.OFF, LogLevel.DEBUG, LogLevel.INFO, LogLevel.WARN, LogLevel.ERROR, LogLevel.FATAL];

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
  
  // hilog输出级别 - 控制是否将日志输出到系统hilog
  // 设置为OFF时，不会输出任何日志到hilog（但仍会记录到日志收集器）
  private hilogOutputLevel: LogLevel = LogLevel.DEBUG;
  
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
   * 设置hilog输出级别
   * 此设置控制日志是否输出到系统的hilog
   * @param level - hilog输出的最低日志级别，设置为OFF则完全关闭hilog输出
   */
  public setHilogOutputLevel(level: LogLevel): void {
    this.hilogOutputLevel = level;
    console.log(`[NGF] hilog输出级别已设置为: ${LOG_LEVEL_NAMES[LOG_LEVEL_VALUES.indexOf(level)]}`);
  }
  
  /**
   * 获取当前的hilog输出级别
   */
  public getHilogOutputLevel(): LogLevel {
    return this.hilogOutputLevel;
  }
  
  /**
   * 检查指定级别的日志是否应该输出到hilog
   * @param level - 要检查的日志级别
   */
  private shouldOutputToHilog(level: LogLevel): boolean {
    // 如果hilog输出级别设置为OFF，则不输出任何日志
    if (this.hilogOutputLevel === LogLevel.OFF) {
      return false;
    }
    // 只有高于或等于hilog输出级别的日志才输出
    return level >= this.hilogOutputLevel;
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
    const levelSymbol = LOG_LEVEL_SYMBOLS.get(level) || '❓ 未知';
    const chineseTag = TAG_MAPPING[tag] || tag;
    const timestamp = this.enableTimestamp ? this.getTimestamp() + ' ' : '';
    const formattedMessage = `${globalPrefix}${timestamp}${levelSymbol} [${chineseTag}] ${message}`;
    // 确保所有日志都被收集，即使在早期启动阶段
    if (!logCollector.isCollectorEnabled()) {
      logCollector.setEnabled(true);
    }
    return formattedMessage;
  }

  private formatArgs(args: (string | number | boolean)[]): string {
    if (args.length <= 0) {
      return '';
    }
    return args.map((item: string | number | boolean) => String(item)).join(' ');
  }

  private formatMessageWithArgs(level: LogLevel, tag: string, message: string,
    args: (string | number | boolean)[]): string {
    const argsText = this.formatArgs(args);
    if (argsText.length <= 0) {
      return this.formatMessage(level, tag, message);
    }
    return this.formatMessage(level, tag, `${message} ${argsText}`);
  }

  /**
   * 🔍 调试级别的日志
   * @param tag - 日志分类标签, 例如 'RenderSystem'
   * @param message - 要输出的日志信息
   * @param args - 其他可选参数
   */
  public debug(tag: string, message: string, ...args: (string | number | boolean)[]): void {
    if (this.currentLevel <= LogLevel.DEBUG) {
      const formattedMessage = this.formatMessageWithArgs(LogLevel.DEBUG, tag, message, args);
      // 仅当hilog输出级别允许时才输出到hilog
      if (this.shouldOutputToHilog(LogLevel.DEBUG)) {
        hilog.debug(LOG_DOMAIN, Flag, `%{public}s`, formattedMessage);
      }
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
      const formattedMessage = this.formatMessageWithArgs(LogLevel.INFO, tag, message, args);
      // 仅当hilog输出级别允许时才输出到hilog
      if (this.shouldOutputToHilog(LogLevel.INFO)) {
        hilog.info(LOG_DOMAIN, Flag, `%{public}s`, formattedMessage);
      }
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
      const formattedMessage = this.formatMessageWithArgs(LogLevel.WARN, tag, message, args);
      // 仅当hilog输出级别允许时才输出到hilog
      if (this.shouldOutputToHilog(LogLevel.WARN)) {
        hilog.warn(LOG_DOMAIN, Flag, `%{public}s`, formattedMessage);
      }
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
      const formattedMessage = this.formatMessageWithArgs(LogLevel.ERROR, tag, message, args);
      // 仅当hilog输出级别允许时才输出到hilog
      if (this.shouldOutputToHilog(LogLevel.ERROR)) {
        hilog.error(LOG_DOMAIN, Flag, `%{public}s`, formattedMessage);
      }
      // 同时发送到日志收集器
      logCollector.addLog(LogLevel.ERROR, tag, message, args);
    }
  }
  
  /**
   * 💀 致命级别的日志
   * @param tag - 日志分类标签
   * @param message - 要输出的日志信息
   * @param args - 其他可选参数
   */
  public fatal(tag: string, message: string, ...args: (string | number | boolean)[]): void {
    if (this.currentLevel <= LogLevel.FATAL) {
      const formattedMessage = this.formatMessageWithArgs(LogLevel.FATAL, tag, message, args);
      // 仅当hilog输出级别允许时才输出到hilog
      if (this.shouldOutputToHilog(LogLevel.FATAL)) {
        hilog.fatal(LOG_DOMAIN, Flag, `%{public}s`, formattedMessage);
      }
      // 同时发送到日志收集器
      logCollector.addLog(LogLevel.FATAL, tag, message, args);
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
  
  /**
   * 🛠️ 从LOG_LEVEL_VALUES索引初始化hilog输出等级
   * 用于应用启动时从SettingsManager加载保存的设置
   * @param levelIndex - 日志等级索引 (0=关闭, 1=DEBUG, 2=INFO, 3=WARN, 4=ERROR, 5=FATAL)
   */
  public initializeHilogLevelFromIndex(levelIndex: number): void {
    if (levelIndex >= 0 && levelIndex < LOG_LEVEL_VALUES.length) {
      this.hilogOutputLevel = LOG_LEVEL_VALUES[levelIndex];
      console.log(`[NGF] 从Settings初始化hilog输出等级: ${LOG_LEVEL_NAMES[levelIndex]}`);
    } else {
      console.log(`[NGF] 无效的日志等级索引: ${levelIndex}，使用默认值DEBUG`);
    }
  }
  
  /**
   * 获取当前hilog输出等级的索引
   * @returns 日志等级索引 (0=关闭, 1=DEBUG, 2=INFO, 3=WARN, 4=ERROR, 5=FATAL)
   */
  public getHilogLevelIndex(): number {
    return LOG_LEVEL_VALUES.indexOf(this.hilogOutputLevel);
  }
}

// 导出一个Logger的单例，方便在全局任何地方使用
export const logger = Logger.getInstance();
