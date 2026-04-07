import { DataManager } from '../Data/DataManager';
import { logCollector, LogEntry, LogFilter } from './LogCollector';
import { LogLevel } from '../../Utils/Logger';

const DEFAULT_SOURCE_DEBUG_MODE_KEY = 'detail_debug_mode';

export class SourceDebugLogManager {
  private static instance: SourceDebugLogManager;

  private readonly dataManager: DataManager = DataManager.getInstance();
  private readonly detailEntryTimes: Map<number, number> = new Map<number, number>();

  public static readonly SOURCE_DEBUG_MODE_KEY: string = DEFAULT_SOURCE_DEBUG_MODE_KEY;

  private constructor() {}

  public static getInstance(): SourceDebugLogManager {
    if (!SourceDebugLogManager.instance) {
      SourceDebugLogManager.instance = new SourceDebugLogManager();
    }
    return SourceDebugLogManager.instance;
  }

  public async isDebugModeEnabled(sourceId: number): Promise<boolean> {
    const record = await this.dataManager.getSourceUserSetting(sourceId, SourceDebugLogManager.SOURCE_DEBUG_MODE_KEY);
    if (!record) {
      return false;
    }
    return this.parseBooleanSetting(record.settingValue);
  }

  public async setDebugModeEnabled(sourceId: number, enabled: boolean): Promise<void> {
    const value = enabled ? '1' : '0';
    await this.dataManager.saveSourceUserSetting(
      sourceId,
      SourceDebugLogManager.SOURCE_DEBUG_MODE_KEY,
      value,
      'boolean'
    );
  }

  public markDetailEntry(sourceId: number, timestamp?: number): number {
    const resolvedTimestamp = timestamp !== undefined ? timestamp : Date.now();
    this.detailEntryTimes.set(sourceId, resolvedTimestamp);
    return resolvedTimestamp;
  }

  public clearDetailEntry(sourceId: number): void {
    this.detailEntryTimes.delete(sourceId);
  }

  public getDetailEntryTime(sourceId: number): number {
    const value = this.detailEntryTimes.get(sourceId);
    if (value === undefined) {
      return 0;
    }
    return value;
  }

  public buildExportText(sourceId: number, sourceName: string, exportTime: number): string {
    const startTime = this.getDetailEntryTime(sourceId);
    const allLogs = logCollector.getAllLogs();
    const firstAvailableTime = allLogs.length > 0 ? allLogs[0].timestamp : 0;
    const lastAvailableTime = allLogs.length > 0 ? allLogs[allLogs.length - 1].timestamp : 0;
    let logs: LogEntry[] = [];
    if (startTime > 0 && exportTime >= startTime) {
      const filter: LogFilter = {
        startTime: startTime,
        endTime: exportTime
      };
      logs = logCollector.getFilteredLogs(filter);
    }
    const truncated = startTime > 0 && firstAvailableTime > 0 && firstAvailableTime > startTime;

    let content = '';
    content += '========================================\n';
    content += '图源调试日志导出\n';
    content += '========================================\n';
    content += `图源名称: ${sourceName || '未命名图源'}\n`;
    content += `图源ID: ${sourceId}\n`;
    content += `导出时间: ${this.formatTimestamp(exportTime)}\n`;
    content += `详情页进入时间: ${startTime > 0 ? this.formatTimestamp(startTime) : '未记录'}\n`;
    content += `当前会话最早日志: ${firstAvailableTime > 0 ? this.formatTimestamp(firstAvailableTime) : '无'}\n`;
    content += `当前会话最新日志: ${lastAvailableTime > 0 ? this.formatTimestamp(lastAvailableTime) : '无'}\n`;
    content += `导出日志数量: ${logs.length}\n`;
    content += `日志缓冲区状态: ${truncated ? '可能已截断' : '完整'}\n`;
    content += '范围说明: 本次应用启动后，从进入该图源详情页开始，到点击“导出日志”为止。\n';
    content += '========================================\n\n';

    if (truncated) {
      content += '注意: 当前详情页进入时间早于日志缓冲区起点，导出内容可能缺少更早的记录。\n\n';
    }

    if (startTime <= 0) {
      content += '未记录到详情页进入时间，无法生成指定区间日志。\n';
      return content;
    }

    if (logs.length === 0) {
      content += '指定时间区间内没有采集到日志。\n';
      return content;
    }

    for (let i = 0; i < logs.length; i++) {
      content += this.formatLogEntry(logs[i]);
      content += '\n';
    }
    return content;
  }

  public buildExportFileName(sourceName: string, exportTime: number): string {
    const safeName = this.normalizeFileNamePart(sourceName);
    const timestamp = this.formatFileTimestamp(exportTime);
    return `source_debug_${safeName}_${timestamp}.txt`;
  }

  private parseBooleanSetting(value: string): boolean {
    const normalized = value.trim().toLowerCase();
    return normalized === '1' || normalized === 'true' || normalized === 'yes' || normalized === 'on';
  }

  private formatLogEntry(entry: LogEntry): string {
    let content = `[${this.formatTimestamp(entry.timestamp)}]`;
    content += ` [${this.getLevelLabel(entry.level)}]`;
    content += ` [${entry.tag}] ${entry.message}`;
    if (entry.args.length > 0) {
      content += ` ${entry.args.join(' ')}`;
    }
    if (entry.details && entry.details.length > 0) {
      content += `\n  details: ${entry.details}`;
    }
    return content;
  }

  private getLevelLabel(level: LogLevel): string {
    if (level === LogLevel.DEBUG) {
      return 'DEBUG';
    }
    if (level === LogLevel.INFO) {
      return 'INFO';
    }
    if (level === LogLevel.WARN) {
      return 'WARN';
    }
    if (level === LogLevel.ERROR) {
      return 'ERROR';
    }
    if (level === LogLevel.FATAL) {
      return 'FATAL';
    }
    return 'UNKNOWN';
  }

  private formatTimestamp(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    const seconds = String(date.getSeconds()).padStart(2, '0');
    const milliseconds = String(date.getMilliseconds()).padStart(3, '0');
    return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}.${milliseconds}`;
  }

  private formatFileTimestamp(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    const seconds = String(date.getSeconds()).padStart(2, '0');
    return `${year}${month}${day}_${hours}${minutes}${seconds}`;
  }

  private normalizeFileNamePart(sourceName: string): string {
    const trimmed = sourceName.trim();
    const fallback = trimmed.length > 0 ? trimmed : 'source';
    const normalized = fallback.replace(/[\\/:*?"<>|\s]+/g, '_');
    const compacted = normalized.replace(/_+/g, '_');
    const sanitized = compacted.replace(/^_+|_+$/g, '');
    return sanitized.length > 0 ? sanitized : 'source';
  }
}

export const sourceDebugLogManager = SourceDebugLogManager.getInstance();
