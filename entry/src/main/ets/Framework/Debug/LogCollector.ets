import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
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

interface PersistedLogEntry {
  t: number;
  l: number;
  g: string;
  m: string;
  a: string[];
  d: string;
}

const LOG_SUB_DIRECTORY: string = 'feedback_logs';
const MAX_FILE_BYTES: number = 8 * 1024 * 1024;
const MAX_FILE_COUNT: number = 10;
const FLUSH_INTERVAL_MILLISECONDS: number = 1000;
const FLUSH_QUEUE_THRESHOLD: number = 500;

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

  // 文件持久化：内存环形缓冲区会被新日志覆盖，历史日志需要落盘才能按时间范围导出。
  private logDirectory: string = '';
  private persistQueue: LogEntry[] = [];
  private persistTimer: number = -1;
  private currentFileSequence: number = 0;
  private currentFileBytes: number = 0;
  private isInitialized: boolean = false;
  private flushRunning: boolean = false;

  private constructor() {}

  public static getInstance(): LogCollector {
    if (!LogCollector.instance) {
      LogCollector.instance = new LogCollector();
    }
    return LogCollector.instance;
  }

  /**
   * 初始化日志落盘目录并启动定时写入（幂等）。
   */
  public async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.isInitialized) {
      return;
    }
    try {
      this.logDirectory = `${context.filesDir}/${LOG_SUB_DIRECTORY}`;
      try {
        await fileIo.mkdir(this.logDirectory);
      } catch (_) {
        // 目录已存在时忽略（首次创建成功或历史版本已建立）。
      }
      await this.cleanupOldFiles();
      this.currentFileSequence = await this.scanCurrentFileSequence();
      this.currentFileBytes = await this.measureCurrentFileSize();
      this.isInitialized = true;
      if (this.persistTimer === -1) {
        this.persistTimer = setInterval((): void => {
          void this.flushPersistQueue();
        }, FLUSH_INTERVAL_MILLISECONDS);
      }
      console.log('[NGF] LogCollector 文件持久化已启动: ' + this.logDirectory);
    } catch (error) {
      // 文件系统不可用时静默降级为纯内存收集。
      console.log('[NGF] LogCollector 文件持久化初始化失败: ' + String(error));
      this.isInitialized = true;
    }
  }

  public async initializeIfNeeded(context: common.UIAbilityContext): Promise<void> {
    if (!this.isInitialized) {
      await this.initialize(context);
    }
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
    this.persistQueue.push(entry);
    if (this.persistQueue.length >= FLUSH_QUEUE_THRESHOLD) {
      void this.flushPersistQueue();
    }
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

  /**
   * 读取落盘日志并按时间范围过滤（不含内存中未落盘部分，调用前请先 forceFlush）。
   */
  public async readFileLogs(startTime: number | undefined, endTime: number | undefined): Promise<LogEntry[]> {
    const result: LogEntry[] = [];
    if (this.logDirectory.length === 0) {
      return result;
    }
    try {
      const names: string[] = await fileIo.listFile(this.logDirectory);
      const sortedNames = this.sortLogFileNames(names);
      for (let i = 0; i < sortedNames.length; i++) {
        const lines = await this.readLogFileLines(`${this.logDirectory}/${sortedNames[i]}`);
        for (let j = 0; j < lines.length; j++) {
          const line = lines[j];
          if (line.length === 0) {
            continue;
          }
          try {
            const parsed = JSON.parse(line) as PersistedLogEntry;
            if (typeof parsed.t !== 'number' || typeof parsed.g !== 'string') {
              continue;
            }
            if (startTime !== undefined && parsed.t < startTime) {
              continue;
            }
            if (endTime !== undefined && parsed.t > endTime) {
              continue;
            }
            result.push({
              id: 0,
              timestamp: parsed.t,
              level: parsed.l as LogLevel,
              tag: parsed.g,
              message: parsed.m,
              args: parsed.a,
              details: parsed.d.length > 0 ? parsed.d : undefined
            });
          } catch (_) {
            // 跳过损坏的行。
          }
        }
      }
      result.sort((left: LogEntry, right: LogEntry): number => left.timestamp - right.timestamp);
    } catch (error) {
      console.log('[NGF] LogCollector 读取落盘日志失败: ' + String(error));
    }
    return result;
  }

  /**
   * 把内存中待写日志同步落盘（导出日志前调用，保证文件包含最新日志）。
   */
  public async forceFlush(): Promise<void> {
    await this.flushPersistQueue();
  }

  public clearLogs(): void {
    this.logs = [];
    this.headIndex = 0;
    this.size = 0;
    this.nextId = 1;
    this.persistQueue = [];
    if (this.logDirectory.length > 0) {
      void this.removeLogFiles();
    }
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

  private async flushPersistQueue(): Promise<void> {
    if (this.flushRunning) {
      return;
    }
    if (!this.isInitialized || this.logDirectory.length === 0) {
      return;
    }
    const pending = this.persistQueue;
    if (pending.length === 0) {
      return;
    }
    this.persistQueue = [];
    this.flushRunning = true;
    try {
      const encoder = new util.TextEncoder();
      let content: string = '';
      for (let i = 0; i < pending.length; i++) {
        const entry = pending[i];
        const persisted: PersistedLogEntry = {
          t: entry.timestamp,
          l: entry.level,
          g: entry.tag,
          m: entry.message,
          a: entry.args.map((item: string | number | boolean): string => String(item)),
          d: entry.details !== undefined ? entry.details : ''
        };
        content += JSON.stringify(persisted) + '\n';
      }
      const bytes = encoder.encodeInto(content);
      await this.appendBytes(bytes);
      this.currentFileBytes += bytes.length;
      if (this.currentFileBytes > MAX_FILE_BYTES) {
        this.currentFileSequence += 1;
        this.currentFileBytes = 0;
        await this.cleanupOldFiles();
      }
    } catch (error) {
      console.log('[NGF] LogCollector 落盘失败: ' + String(error));
      // 失败时丢弃这批日志，避免无限重试占用内存。
    } finally {
      this.flushRunning = false;
    }
  }

  private async appendBytes(bytes: Uint8Array): Promise<void> {
    if (this.logDirectory.length === 0 || bytes.length === 0) {
      return;
    }
    const path = `${this.logDirectory}/manxia-log-${this.currentFileSequence}.log`;
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.APPEND);
    try {
      let written: number = 0;
      while (written < bytes.length) {
        const buffer = new ArrayBuffer(bytes.length - written);
        new Uint8Array(buffer).set(bytes.subarray(written));
        const writtenBytes = await fileIo.write(file.fd, buffer, { length: buffer.byteLength });
        if (writtenBytes <= 0) {
          throw new Error('写入日志文件失败');
        }
        written += writtenBytes;
      }
    } finally {
      await fileIo.close(file);
    }
  }

  private async scanCurrentFileSequence(): Promise<number> {
    try {
      const names: string[] = await fileIo.listFile(this.logDirectory);
      let maxSequence: number = -1;
      for (let i = 0; i < names.length; i++) {
        const match = /^manxia-log-(\d+)\.log$/.exec(names[i]);
        if (match !== null) {
          const value = Number(match[1]);
          if (Number.isFinite(value) && value > maxSequence) {
            maxSequence = value;
          }
        }
      }
      return maxSequence + 1;
    } catch (_) {
      return 0;
    }
  }

  private async measureCurrentFileSize(): Promise<number> {
    try {
      const path = `${this.logDirectory}/manxia-log-${this.currentFileSequence}.log`;
      const file = await fileIo.open(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      try {
        const stat = await fileIo.stat(file.fd);
        return stat.size;
      } finally {
        await fileIo.close(file);
      }
    } catch (_) {
      return 0;
    }
  }

  private async cleanupOldFiles(): Promise<void> {
    if (this.logDirectory.length === 0) {
      return;
    }
    try {
      const names: string[] = await fileIo.listFile(this.logDirectory);
      const sortedNames = this.sortLogFileNames(names);
      while (sortedNames.length > MAX_FILE_COUNT) {
        const oldest = sortedNames.shift();
        if (oldest !== undefined) {
          await fileIo.unlink(`${this.logDirectory}/${oldest}`);
        }
      }
    } catch (error) {
      console.log('[NGF] LogCollector 清理旧日志文件失败: ' + String(error));
    }
  }

  private async removeLogFiles(): Promise<void> {
    try {
      const names: string[] = await fileIo.listFile(this.logDirectory);
      for (let i = 0; i < names.length; i++) {
        if (names[i].startsWith('manxia-log-')) {
          await fileIo.unlink(`${this.logDirectory}/${names[i]}`);
        }
      }
      this.currentFileSequence = 0;
      this.currentFileBytes = 0;
    } catch (error) {
      console.log('[NGF] LogCollector 删除日志文件失败: ' + String(error));
    }
  }

  private async readLogFileLines(path: string): Promise<string[]> {
    const result: string[] = [];
    try {
      const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      try {
        const stat = await fileIo.stat(file.fd);
        if (stat.size <= 0) {
          return result;
        }
        const buffer = new ArrayBuffer(stat.size);
        const readBytes = await fileIo.read(file.fd, buffer, { length: stat.size });
        const decoder = util.TextDecoder.create('utf-8');
        const text = decoder.decodeToString(new Uint8Array(buffer).subarray(0, readBytes));
        const parts = text.split('\n');
        for (let i = 0; i < parts.length; i++) {
          result.push(parts[i].trim());
        }
      } finally {
        await fileIo.close(file);
      }
    } catch (error) {
      console.log('[NGF] LogCollector 读取日志文件失败: ' + String(error));
    }
    return result;
  }

  private sortLogFileNames(names: string[]): string[] {
    const sorted = names.filter((name: string): boolean => /^manxia-log-\d+\.log$/.test(name));
    sorted.sort((left: string, right: string): number => {
      const leftMatch = /^manxia-log-(\d+)\.log$/.exec(left);
      const rightMatch = /^manxia-log-(\d+)\.log$/.exec(right);
      const leftValue = leftMatch !== null ? Number(leftMatch[1]) : 0;
      const rightValue = rightMatch !== null ? Number(rightMatch[1]) : 0;
      return leftValue - rightValue;
    });
    return sorted;
  }
}

export const logCollector = LogCollector.getInstance();
