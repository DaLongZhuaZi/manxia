// 文件路径: src/main/ets/Framework/Debug/LogCollector.ets
/**
 * 日志收集器
 * 用于收集和管理游戏内的日志输出
 */
 
import { LogLevel } from '../../Utils/Logger';

/**
 * 日志条目接口
 */
export interface LogEntry {
  id: number;
  timestamp: number;
  level: LogLevel;
  tag: string;
  message: string;
  args: (string | number | boolean)[];
  details?: string; // 可选的详细信息
}

/**
 * 日志过滤器接口
 */
export interface LogFilter {
  level?: LogLevel;
  tag?: string;
  searchText?: string;
  startTime?: number;
  endTime?: number;
}

/**
 * 日志统计接口
 */
export interface LogStats {
  total: number;
  debug: number;
  info: number;
  warn: number;
  error: number;
}

/**
 * 日志收集器
 * 用于收集和管理游戏内的日志输出
 */
export class LogCollector {
  private static instance: LogCollector;
  private logs: LogEntry[] = [];
  private maxLogCount: number = 1000; // 最大日志条数
  private nextId: number = 1;
  private isEnabled: boolean = true;
  private listeners: ((entry: LogEntry) => void)[] = [];

  private constructor() {}

  public static getInstance(): LogCollector {
    if (!LogCollector.instance) {
      LogCollector.instance = new LogCollector();
    }
    return LogCollector.instance;
  }

  /**
   * 添加日志条目
   */
  public addLog(level: LogLevel, tag: string, message: string, args: (string | number | boolean)[] = []): void {
    if (!this.isEnabled) {
      return;
    }

    const entry: LogEntry = {
      id: this.nextId++,
      timestamp: Date.now(),
      level,
      tag,
      message,
      args
    };

    this.logs.push(entry);

    // 限制日志数量
    if (this.logs.length > this.maxLogCount) {
      this.logs.shift();
    }

    // 通知监听器
    this.notifyListeners(entry);
  }

  /**
   * 获取所有日志
   */
  public getAllLogs(): LogEntry[] {
    const result: LogEntry[] = [];
    for (let i = 0; i < this.logs.length; i++) {
      result.push(this.logs[i]);
    }
    return result;
  }

  /**
   * 根据过滤器获取日志
   */
  public getFilteredLogs(filter: LogFilter): LogEntry[] {
    const result: LogEntry[] = [];
    
    for (let i = 0; i < this.logs.length; i++) {
      const log: LogEntry = this.logs[i];
      
      // 级别过滤
      if (filter.level !== undefined && log.level < filter.level) {
        continue;
      }
      
      // 标签过滤
      if (filter.tag && !log.tag.toLowerCase().includes(filter.tag.toLowerCase())) {
        continue;
      }
      
      // 搜索文本过滤
      if (filter.searchText) {
        const searchLower = filter.searchText.toLowerCase();
        const messageMatch = log.message.toLowerCase().includes(searchLower);
        const tagMatch = log.tag.toLowerCase().includes(searchLower);
        if (!messageMatch && !tagMatch) {
          continue;
        }
      }
      
      // 时间范围过滤
      if (filter.startTime && log.timestamp < filter.startTime) {
        continue;
      }
      if (filter.endTime && log.timestamp > filter.endTime) {
        continue;
      }
      
      result.push(log);
    }
    
    return result;
  }

  /**
   * 清空日志
   */
  public clearLogs(): void {
    this.logs = [];
    this.nextId = 1;
  }

  /**
   * 设置最大日志数量
   */
  public setMaxLogCount(count: number): void {
    this.maxLogCount = Math.max(100, count);
    
    // 如果当前日志数量超过新的限制，删除旧的日志
    while (this.logs.length > this.maxLogCount) {
      this.logs.shift();
    }
  }

  /**
   * 启用/禁用日志收集
   */
  public setEnabled(enabled: boolean): void {
    this.isEnabled = enabled;
  }

  /**
   * 检查是否启用
   */
  public isCollectorEnabled(): boolean {
    return this.isEnabled;
  }

  /**
   * 添加日志监听器
   */
  public addListener(listener: (entry: LogEntry) => void): void {
    this.listeners.push(listener);
  }

  /**
   * 移除日志监听器
   */
  public removeListener(listener: (entry: LogEntry) => void): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /**
   * 通知所有监听器
   */
  private notifyListeners(entry: LogEntry): void {
    for (let i = 0; i < this.listeners.length; i++) {
      try {
        this.listeners[i](entry);
      } catch (error) {
        // 忽略监听器错误，避免影响日志收集
      }
    }
  }

  /**
   * 获取日志统计信息
   */
  public getLogStats(): LogStats {
    const stats: LogStats = {
      total: this.logs.length,
      debug: 0,
      info: 0,
      warn: 0,
      error: 0
    };

    for (let i = 0; i < this.logs.length; i++) {
      const log: LogEntry = this.logs[i];
      switch (log.level) {
        case LogLevel.DEBUG:
          stats.debug++;
          break;
        case LogLevel.INFO:
          stats.info++;
          break;
        case LogLevel.WARN:
          stats.warn++;
          break;
        case LogLevel.ERROR:
          stats.error++;
          break;
      }
    }

    return stats;
  }
}

// 导出单例实例
export const logCollector = LogCollector.getInstance();