import { LogLevel } from '../../Utils/Logger';

export interface LogEntry {
  id: number;
  timestamp: number;
  level: LogLevel;
  tag: string;
  message: string;
  args: (string | number | boolean)[];
  details?: string;
}

export interface LogFilter {
  level?: LogLevel;
  tag?: string;
  searchText?: string;
  startTime?: number;
  endTime?: number;
}

export interface LogStats {
  total: number;
  debug: number;
  info: number;
  warn: number;
  error: number;
}

export class LogCollector {
  private static instance: LogCollector;

  // Ring buffer storage to avoid O(n) shift() on high-frequency logging.
  private logs: LogEntry[] = [];
  private maxLogCount: number = 5000;
  private headIndex: number = 0;
  private size: number = 0;

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

    this.pushEntry(entry);
    this.notifyListeners(entry);
  }

  public getAllLogs(): LogEntry[] {
    return this.getOrderedLogs();
  }

  public getFilteredLogs(filter: LogFilter): LogEntry[] {
    const orderedLogs = this.getOrderedLogs();
    const result: LogEntry[] = [];

    const searchLower = filter.searchText ? filter.searchText.toLowerCase() : '';
    const tagLower = filter.tag ? filter.tag.toLowerCase() : '';

    for (let i = 0; i < orderedLogs.length; i++) {
      const log = orderedLogs[i];

      if (filter.level !== undefined && log.level < filter.level) {
        continue;
      }

      if (tagLower.length > 0 && !log.tag.toLowerCase().includes(tagLower)) {
        continue;
      }

      if (searchLower.length > 0) {
        const messageMatch = log.message.toLowerCase().includes(searchLower);
        const tagMatch = log.tag.toLowerCase().includes(searchLower);
        if (!messageMatch && !tagMatch) {
          continue;
        }
      }

      if (filter.startTime !== undefined && log.timestamp < filter.startTime) {
        continue;
      }
      if (filter.endTime !== undefined && log.timestamp > filter.endTime) {
        continue;
      }

      result.push(log);
    }

    return result;
  }

  public clearLogs(): void {
    this.logs = [];
    this.headIndex = 0;
    this.size = 0;
    this.nextId = 1;
  }

  public setMaxLogCount(count: number): void {
    const safeCount = Number.isFinite(count) ? Math.floor(count) : 100;
    const normalizedCount = Math.max(100, safeCount);
    if (normalizedCount === this.maxLogCount) {
      return;
    }

    const oldLogs = this.getOrderedLogs();
    this.maxLogCount = normalizedCount;
    this.logs = [];
    this.headIndex = 0;
    this.size = 0;

    const start = oldLogs.length > this.maxLogCount ? oldLogs.length - this.maxLogCount : 0;
    for (let i = start; i < oldLogs.length; i++) {
      this.pushEntry(oldLogs[i]);
    }
  }

  public setEnabled(enabled: boolean): void {
    this.isEnabled = enabled;
  }

  public isCollectorEnabled(): boolean {
    return this.isEnabled;
  }

  public addListener(listener: (entry: LogEntry) => void): void {
    this.listeners.push(listener);
  }

  public removeListener(listener: (entry: LogEntry) => void): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  public getLogStats(): LogStats {
    const orderedLogs = this.getOrderedLogs();
    const stats: LogStats = {
      total: orderedLogs.length,
      debug: 0,
      info: 0,
      warn: 0,
      error: 0
    };

    for (let i = 0; i < orderedLogs.length; i++) {
      const log = orderedLogs[i];
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

  private pushEntry(entry: LogEntry): void {
    if (this.maxLogCount <= 0) {
      return;
    }

    if (this.size < this.maxLogCount) {
      const tailIndex = (this.headIndex + this.size) % this.maxLogCount;
      this.logs[tailIndex] = entry;
      this.size++;
      return;
    }

    this.logs[this.headIndex] = entry;
    this.headIndex = (this.headIndex + 1) % this.maxLogCount;
  }

  private getOrderedLogs(): LogEntry[] {
    const result: LogEntry[] = [];
    if (this.size === 0) {
      return result;
    }

    for (let i = 0; i < this.size; i++) {
      const index = (this.headIndex + i) % this.maxLogCount;
      const log = this.logs[index];
      if (log !== undefined) {
        result.push(log);
      }
    }

    return result;
  }

  private notifyListeners(entry: LogEntry): void {
    for (let i = 0; i < this.listeners.length; i++) {
      try {
        this.listeners[i](entry);
      } catch {
        // Keep logging path resilient even if a listener fails.
      }
    }
  }
}

export const logCollector = LogCollector.getInstance();
