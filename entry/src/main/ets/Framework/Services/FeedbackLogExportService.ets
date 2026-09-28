import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { LogCollector, LogEntry, LogFilter } from 'manxia_core/src/main/ets/Framework/Debug/LogCollector';
import { LogLevel } from 'manxia_core/src/main/ets/Utils/Logger';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'FeedbackLogExportService';
const LOG_DIRECTORY = 'feedback/pending';
const MAX_LOG_BYTES = 10 * 1024 * 1024;

export interface FeedbackLogExportResult {
  path: string;
  name: string;
  size: number;
  count: number;
  startTime: number | undefined;
  endTime: number | undefined;
}

export class FeedbackLogExportService {
  private static instance: FeedbackLogExportService | null = null;
  private readonly logCollector: LogCollector = LogCollector.getInstance();

  private constructor() {}

  public static getInstance(): FeedbackLogExportService {
    if (FeedbackLogExportService.instance === null) {
      FeedbackLogExportService.instance = new FeedbackLogExportService();
    }
    return FeedbackLogExportService.instance;
  }

  public async exportLogs(
    context: common.UIAbilityContext,
    startTime: number | undefined,
    endTime: number | undefined
  ): Promise<FeedbackLogExportResult> {
    // 先确保日志落盘可用，并把内存中最新日志刷入文件，保证按时间范围导出完整。
    await this.logCollector.initializeIfNeeded(context);
    await this.logCollector.forceFlush();
    let logs: LogEntry[] = await this.logCollector.readFileLogs(startTime, endTime);
    if (logs.length === 0) {
      // 文件持久化不可用（例如存储异常）时降级为内存日志。
      const filter: LogFilter = {
        startTime: startTime,
        endTime: endTime
      };
      logs = this.logCollector.getFilteredLogs(filter);
    }
    const fullContent: string = this.buildContent(logs, startTime, endTime);
    const content: string = this.limitContent(fullContent);
    const encoder = new util.TextEncoder();
    const bytes = encoder.encodeInto(content);
    const directory = `${context.filesDir}/${LOG_DIRECTORY}`;
    await this.ensureDirectory(directory);
    const name = `manxia-app-logs-${Date.now()}.log`;
    const path = `${directory}/${name}`;
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
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
    logger.info(TAG, `已生成反馈日志: ${name}, count=${logs.length}, bytes=${bytes.length}`);
    return {
      path: path,
      name: name,
      size: bytes.length,
      count: logs.length,
      startTime: startTime,
      endTime: endTime
    };
  }

  private buildContent(logs: LogEntry[], startTime: number | undefined, endTime: number | undefined): string {
    const lines: string[] = [];
    lines.push('漫匣 APP 诊断日志');
    lines.push(`导出时间: ${new Date().toISOString()}`);
    lines.push(`时间范围: ${this.formatRange(startTime, endTime)}`);
    lines.push(`日志数量: ${logs.length}`);
    lines.push('说明: 日志中的访问令牌、设备标识和 IP 地址已脱敏。');
    lines.push('');
    for (const log of logs) {
      const args = log.args.length > 0 ? ` args=${log.args.map((item: string | number | boolean) => this.redact(String(item))).join(' | ')}` : '';
      const details = log.details ? ` details=${this.redact(log.details)}` : '';
      lines.push(`[${new Date(log.timestamp).toISOString()}] [${this.levelName(log.level)}] [${this.redact(log.tag)}] ${this.redact(log.message)}${args}${details}`);
    }
    return lines.join('\n');
  }

  private limitContent(content: string): string {
    const encoder = new util.TextEncoder();
    const bytes = encoder.encodeInto(content);
    if (bytes.length <= MAX_LOG_BYTES) {
      return content;
    }
    const suffix = '\n\n[日志已达到 10 MiB 限制，已保留开头部分。]';
    const suffixBytes = encoder.encodeInto(suffix).length;
    const targetBytes = MAX_LOG_BYTES - suffixBytes;
    let low: number = 0;
    let high: number = content.length;
    while (low < high) {
      const middle: number = Math.ceil((low + high) / 2);
      const candidateBytes: number = encoder.encodeInto(content.substring(0, middle)).length;
      if (candidateBytes <= targetBytes) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    let prefix: string = content.substring(0, low);
    const lastCodeUnit: number = prefix.length > 0 ? prefix.charCodeAt(prefix.length - 1) : 0;
    if (lastCodeUnit >= 0xD800 && lastCodeUnit <= 0xDBFF) {
      prefix = prefix.substring(0, prefix.length - 1);
    }
    return `${prefix}${suffix}`;
  }

  private formatRange(startTime: number | undefined, endTime: number | undefined): string {
    const start = startTime === undefined ? '最早可用' : new Date(startTime).toISOString();
    const end = endTime === undefined ? '当前' : new Date(endTime).toISOString();
    return `${start} ~ ${end}`;
  }

  private levelName(level: LogLevel): string {
    if (level === LogLevel.DEBUG) return 'DEBUG';
    if (level === LogLevel.INFO) return 'INFO';
    if (level === LogLevel.WARN) return 'WARN';
    if (level === LogLevel.ERROR) return 'ERROR';
    if (level === LogLevel.FATAL) return 'FATAL';
    return 'OFF';
  }

  private redact(value: string): string {
    let result = value;
    result = result.replace(/\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/gi, '[UUID_REDACTED]');
    result = result.replace(/(authorization\s*[:=]\s*bearer\s+)[^\s,;]+/gi, '$1[REDACTED]');
    result = result.replace(/(token|secret|password|api[-_]?key)\s*[:=]\s*[^\s,;]+/gi, '$1=[REDACTED]');
    result = result.replace(/(uuid|device[-_ ]?id|serial[-_ ]?number|imei)\s*[:=]\s*[^\s,;]+/gi, '$1=[REDACTED]');
    result = result.replace(/\b(?:\d{1,3}\.){3}\d{1,3}\b/g, '[IP_REDACTED]');
    result = result.replace(/\b[0-9a-f]{32,64}\b/gi, '[ID_REDACTED]');
    return result;
  }

  private async ensureDirectory(path: string): Promise<void> {
    try {
      const stat = await fileIo.stat(path);
      if (!stat.isDirectory()) {
        throw new Error(`路径不是目录: ${path}`);
      }
    } catch (_) {
      await fileIo.mkdir(path, true);
    }
  }
}

export const feedbackLogExportService = FeedbackLogExportService.getInstance();
