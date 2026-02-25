// 文件路径: entry/src/main/ets/Framework/Debug/ErrorRecordManager.ets
/**
 * 统一错误记录管理器
 * 管理来自 ErrorMonitorService（运行时错误）和 CrashRecorderService（闪退记录）的结构化错误信息，
 * 以 JSON 持久化到沙箱，供错误管理页面展示和导出。
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { deviceInfo } from '@kit.BasicServicesKit';

const TAG = 'ErrorRecordManager';

/**
 * 错误来源类型
 */
export enum ErrorSource {
  RUNTIME_ERROR = 'runtime',   // 运行时错误（ErrorMonitorService）
  CRASH = 'crash',             // 闪退（CrashRecorderService）
  NETWORK_ERROR = 'network'    // 网络相关错误
}

/**
 * 统一错误记录
 */
export interface ErrorRecord {
  id: string;                  // 唯一ID
  source: ErrorSource;         // 来源
  timestamp: number;           // 发生时间
  timeStr: string;             // 时间字符串
  tag: string;                 // 来源标签/模块
  message: string;             // 错误消息
  stackTrace: string;          // 堆栈（如有）
  level: string;               // 级别: ERROR / FATAL / CRASH
  logFileName: string;         // 关联的日志文件名
  deviceModel: string;         // 设备型号
  osVersion: string;           // 系统版本
}

/**
 * 错误统计摘要
 */
export interface ErrorSummary {
  total: number;
  runtimeErrors: number;
  crashes: number;
  networkErrors: number;
  topTags: TagCount[];         // 出现最多的 tag
  firstTime: number;           // 最早一条
  lastTime: number;            // 最近一条
}

export interface TagCount {
  tag: string;
  count: number;
}

/**
 * 统一错误记录管理器
 */
export class ErrorRecordManager {
  private static instance: ErrorRecordManager;
  private context: common.UIAbilityContext | null = null;
  private records: ErrorRecord[] = [];
  private recordsFilePath: string = '';
  private isLoaded: boolean = false;
  private static readonly MAX_RECORDS: number = 200;

  private constructor() {}

  public static getInstance(): ErrorRecordManager {
    if (!ErrorRecordManager.instance) {
      ErrorRecordManager.instance = new ErrorRecordManager();
    }
    return ErrorRecordManager.instance;
  }

  /**
   * 初始化（在 EntryAbility 中调用）
   */
  public initialize(context: common.UIAbilityContext): void {
    try {
      this.context = context;
      this.recordsFilePath = `${context.filesDir}/error_records.json`;
      this.loadRecords();
      console.log(`[NGF] ${TAG}: ✅ 错误记录管理器初始化完成，已有 ${this.records.length} 条记录`);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: 初始化失败: ${msg}`);
    }
  }

  /**
   * 添加一条运行时错误记录
   */
  public addRuntimeError(tag: string, message: string, level: string, logFileName: string): string {
    const now = Date.now();
    const record: ErrorRecord = {
      id: `rt_${now}_${Math.floor(Math.random() * 10000)}`,
      source: ErrorSource.RUNTIME_ERROR,
      timestamp: now,
      timeStr: this.formatDateTime(now),
      tag: tag,
      message: message,
      stackTrace: '',
      level: level,
      logFileName: logFileName,
      deviceModel: this.getDeviceModel(),
      osVersion: this.getOsVersion()
    };
    this.pushRecord(record);
    return record.id;
  }

  /**
   * 添加一条闪退记录
   */
  public addCrashRecord(errorMessage: string, stackTrace: string, logFileName: string): void {
    const now = Date.now();
    const record: ErrorRecord = {
      id: `cr_${now}_${Math.floor(Math.random() * 10000)}`,
      source: ErrorSource.CRASH,
      timestamp: now,
      timeStr: this.formatDateTime(now),
      tag: 'CRASH',
      message: errorMessage,
      stackTrace: stackTrace,
      level: 'CRASH',
      logFileName: logFileName,
      deviceModel: this.getDeviceModel(),
      osVersion: this.getOsVersion()
    };
    this.pushRecord(record);
  }

  /**
   * 添加一条网络错误记录
   */
  public addNetworkError(tag: string, message: string, level: string, logFileName: string): string {
    const now = Date.now();
    const record: ErrorRecord = {
      id: `net_${now}_${Math.floor(Math.random() * 10000)}`,
      source: ErrorSource.NETWORK_ERROR,
      timestamp: now,
      timeStr: this.formatDateTime(now),
      tag: tag,
      message: message,
      stackTrace: '',
      level: level,
      logFileName: logFileName,
      deviceModel: this.getDeviceModel(),
      osVersion: this.getOsVersion()
    };
    this.pushRecord(record);
    return record.id;
  }

  private pushRecord(record: ErrorRecord): void {
    this.records.push(record);
    // 限制数量
    while (this.records.length > ErrorRecordManager.MAX_RECORDS) {
      this.records.shift();
    }
    this.saveRecords();
  }

  /**
   * 获取所有记录（按时间倒序）
   */
  public getAllRecords(): ErrorRecord[] {
    const result = this.records.slice();
    result.sort((a: ErrorRecord, b: ErrorRecord) => b.timestamp - a.timestamp);
    return result;
  }

  /**
   * 按来源过滤
   */
  public getRecordsBySource(source: ErrorSource): ErrorRecord[] {
    return this.getAllRecords().filter((r: ErrorRecord) => r.source === source);
  }

  /**
   * 获取错误统计摘要
   */
  public getSummary(): ErrorSummary {
    const tagMap = new Map<string, number>();
    let runtimeCount = 0;
    let crashCount = 0;
    let networkCount = 0;
    let firstTime = Number.MAX_SAFE_INTEGER;
    let lastTime = 0;

    for (let i = 0; i < this.records.length; i++) {
      const r = this.records[i];
      if (r.source === ErrorSource.RUNTIME_ERROR) {
        runtimeCount++;
      } else if (r.source === ErrorSource.CRASH) {
        crashCount++;
      } else if (r.source === ErrorSource.NETWORK_ERROR) {
        networkCount++;
      }
      if (r.timestamp < firstTime) {
        firstTime = r.timestamp;
      }
      if (r.timestamp > lastTime) {
        lastTime = r.timestamp;
      }
      const cur = tagMap.get(r.tag) || 0;
      tagMap.set(r.tag, cur + 1);
    }

    // 按出现次数排序取前10
    const topTags: TagCount[] = [];
    tagMap.forEach((count: number, tag: string) => {
      topTags.push({ tag, count });
    });
    topTags.sort((a: TagCount, b: TagCount) => b.count - a.count);

    return {
      total: this.records.length,
      runtimeErrors: runtimeCount,
      crashes: crashCount,
      networkErrors: networkCount,
      topTags: topTags.slice(0, 10),
      firstTime: firstTime === Number.MAX_SAFE_INTEGER ? 0 : firstTime,
      lastTime: lastTime
    };
  }

  /**
   * 删除单条记录
   */
  public deleteRecord(id: string): void {
    this.records = this.records.filter((r: ErrorRecord) => r.id !== id);
    this.saveRecords();
  }

  /**
   * 清空所有记录
   */
  public clearAll(): void {
    this.records = [];
    this.saveRecords();
  }

  /**
   * 更新指定记录的日志文件名
   */
  public updateRecordLogFileName(id: string, fileName: string): void {
    for (let i = this.records.length - 1; i >= 0; i--) {
      if (this.records[i].id === id) {
        this.records[i].logFileName = fileName;
        this.saveRecords();
        return;
      }
    }
  }

  /**
   * 导出单条记录为格式化文本
   */
  public exportSingleRecord(record: ErrorRecord): string {
    const sections: string[] = [];
    sections.push('╔══════════════════════════════════════════════════════════════╗');
    sections.push('║                    漫匣 错误详情报告                         ║');
    sections.push('╚══════════════════════════════════════════════════════════════╝');
    sections.push('');
    sections.push(`▶ 错误ID: ${record.id}`);
    sections.push(`▶ 类型: ${record.source === ErrorSource.CRASH ? '闪退 (CRASH)' : record.source === ErrorSource.NETWORK_ERROR ? '网络错误 (NETWORK)' : '运行时错误 (RUNTIME)'}`);
    sections.push(`▶ 时间: ${record.timeStr}`);
    sections.push(`▶ 级别: ${record.level}`);
    sections.push(`▶ 来源模块: ${record.tag}`);
    sections.push(`▶ 设备: ${record.deviceModel}`);
    sections.push(`▶ 系统: ${record.osVersion}`);
    sections.push('');
    sections.push('▶ 错误消息');
    sections.push(`  ${record.message}`);
    sections.push('');
    if (record.stackTrace) {
      sections.push('▶ 堆栈信息');
      sections.push(record.stackTrace);
      sections.push('');
    }
    if (record.logFileName) {
      sections.push(`▶ 关联日志文件: ${record.logFileName}`);
    }
    return sections.join('\n');
  }

  /**
   * 导出多条记录为格式化文本（合并导出）
   */
  public exportMultipleRecords(records: ErrorRecord[]): string {
    // 按时间排序（旧→新）
    const sorted = records.slice().sort((a: ErrorRecord, b: ErrorRecord) => a.timestamp - b.timestamp);
    const sections: string[] = [];

    sections.push('╔══════════════════════════════════════════════════════════════╗');
    sections.push('║                  漫匣 错误合并导出报告                       ║');
    sections.push('╚══════════════════════════════════════════════════════════════╝');
    sections.push('');
    sections.push(`▶ 导出时间: ${this.formatDateTime(Date.now())}`);
    sections.push(`▶ 错误总数: ${sorted.length} 条`);
    sections.push('');

    // 设备信息
    sections.push('▶ 设备信息');
    sections.push(`  型号: ${this.getDeviceModel()}`);
    sections.push(`  系统: ${this.getOsVersion()}`);
    sections.push('');

    // 统计摘要
    let runtimeCount = 0;
    let crashCount = 0;
    let networkCount = 0;
    const tagSet = new Map<string, number>();
    for (let i = 0; i < sorted.length; i++) {
      const r = sorted[i];
      if (r.source === ErrorSource.CRASH) {
        crashCount++;
      } else if (r.source === ErrorSource.NETWORK_ERROR) {
        networkCount++;
      } else {
        runtimeCount++;
      }
      const cur = tagSet.get(r.tag) || 0;
      tagSet.set(r.tag, cur + 1);
    }
    sections.push('▶ 统计摘要');
    sections.push(`  运行时错误: ${runtimeCount} 条`);
    sections.push(`  网络错误: ${networkCount} 条`);
    sections.push(`  闪退记录: ${crashCount} 条`);
    sections.push(`  时间跨度: ${sorted.length > 0 ? sorted[0].timeStr : '-'} ~ ${sorted.length > 0 ? sorted[sorted.length - 1].timeStr : '-'}`);
    sections.push('');
    sections.push('  涉及模块:');
    tagSet.forEach((count: number, tag: string) => {
      sections.push(`    • ${tag}: ${count} 次`);
    });
    sections.push('');

    // 逐条详情
    sections.push('═'.repeat(62));
    sections.push('▶ 错误详情列表');
    sections.push('═'.repeat(62));
    sections.push('');

    for (let i = 0; i < sorted.length; i++) {
      const r = sorted[i];
      const idx = i + 1;
      sections.push(`────────────────── 第 ${idx}/${sorted.length} 条 ──────────────────`);
      sections.push(`  ID: ${r.id}`);
      sections.push(`  类型: ${r.source === ErrorSource.CRASH ? '闪退' : r.source === ErrorSource.NETWORK_ERROR ? '网络错误' : '运行时错误'}`);
      sections.push(`  时间: ${r.timeStr}`);
      sections.push(`  级别: ${r.level}`);
      sections.push(`  模块: ${r.tag}`);
      sections.push(`  消息: ${r.message}`);
      if (r.stackTrace) {
        sections.push(`  堆栈:`);
        // 缩进堆栈的每一行
        const stackLines = r.stackTrace.split('\n');
        for (let j = 0; j < stackLines.length; j++) {
          sections.push(`    ${stackLines[j]}`);
        }
      }
      if (r.logFileName) {
        sections.push(`  日志文件: ${r.logFileName}`);
      }
      sections.push('');
    }

    sections.push('═'.repeat(62));
    sections.push('报告结束');
    sections.push('═'.repeat(62));

    return sections.join('\n');
  }

  // ─── 持久化 ───

  private loadRecords(): void {
    try {
      try {
        fs.accessSync(this.recordsFilePath);
      } catch {
        this.records = [];
        this.isLoaded = true;
        return;
      }

      const file = fs.openSync(this.recordsFilePath, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(this.recordsFilePath);
      if (stat.size === 0) {
        fs.closeSync(file);
        this.records = [];
        this.isLoaded = true;
        return;
      }
      const buf = new ArrayBuffer(Number(stat.size));
      fs.readSync(file.fd, buf);
      fs.closeSync(file);

      const decoder = new util.TextDecoder('utf-8');
      const jsonStr = decoder.decodeToString(new Uint8Array(buf));
      const parsed = JSON.parse(jsonStr) as ErrorRecord[];
      this.records = Array.isArray(parsed) ? parsed : [];
      this.isLoaded = true;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: 加载错误记录失败: ${msg}`);
      this.records = [];
      this.isLoaded = true;
    }
  }

  private saveRecords(): void {
    try {
      if (!this.recordsFilePath) {
        return;
      }
      const jsonStr = JSON.stringify(this.records);
      const file = fs.openSync(this.recordsFilePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, jsonStr);
      fs.closeSync(file);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: 保存错误记录失败: ${msg}`);
    }
  }

  // ─── 工具方法 ───

  private formatDateTime(timestamp: number): string {
    const d = new Date(timestamp);
    const year = d.getFullYear();
    const month = (d.getMonth() + 1).toString().padStart(2, '0');
    const day = d.getDate().toString().padStart(2, '0');
    const hours = d.getHours().toString().padStart(2, '0');
    const minutes = d.getMinutes().toString().padStart(2, '0');
    const seconds = d.getSeconds().toString().padStart(2, '0');
    const ms = d.getMilliseconds().toString().padStart(3, '0');
    return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}.${ms}`;
  }

  private getDeviceModel(): string {
    try {
      return `${deviceInfo.brand || ''} ${deviceInfo.productModel || ''}`.trim() || '未知';
    } catch {
      return '未知';
    }
  }

  private getOsVersion(): string {
    try {
      return deviceInfo.osFullName || '未知';
    } catch {
      return '未知';
    }
  }
}

export function getErrorRecordManager(): ErrorRecordManager {
  return ErrorRecordManager.getInstance();
}
