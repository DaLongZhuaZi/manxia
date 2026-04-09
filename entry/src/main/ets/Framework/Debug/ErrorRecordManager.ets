// 文件路径: entry/src/main/ets/Framework/Debug/ErrorRecordManager.ets
/**
 * 统一错误记录管理器
 * 管理来自 ErrorMonitorService（运行时错误）和 CrashRecorderService（闪退记录）的结构化错误信息，
 * 并持久化到沙箱 JSON 文件。
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { deviceInfo } from '@kit.BasicServicesKit';

const TAG = 'ErrorRecordManager';

/** 错误来源类型 */
export enum ErrorSource {
  RUNTIME_ERROR = 'runtime',
  CRASH = 'crash',
  NETWORK_ERROR = 'network'
}

/** 错误分类（按功能区域） */
export enum ErrorCategory {
  UNKNOWN = 'unknown',
  NETWORK = 'network',
  DOWNLOAD = 'download',
  STORAGE = 'storage',
  DATA = 'data',
  PARSER = 'parser',
  SOURCE = 'source',
  WEBVIEW = 'webview',
  AUTH = 'auth',
  SYNC = 'sync',
  UI = 'ui',
  SYSTEM = 'system'
}

/** 统一错误记录 */
export interface ErrorRecord {
  id: string;
  source: ErrorSource;
  category: ErrorCategory;
  timestamp: number;
  timeStr: string;
  tag: string;
  message: string;
  stackTrace: string;
  level: string;
  logFileName: string;
  deviceModel: string;
  osVersion: string;
}

export interface ErrorSummary {
  total: number;
  runtimeErrors: number;
  crashes: number;
  networkErrors: number;
  categoryCounts: CategoryCount[];
  topTags: TagCount[];
  firstTime: number;
  lastTime: number;
}

export interface TagCount {
  tag: string;
  count: number;
}

export interface CategoryCount {
  category: ErrorCategory;
  count: number;
}

export class ErrorRecordManager {
  private static instance: ErrorRecordManager;
  private context: common.UIAbilityContext | null = null;
  private records: ErrorRecord[] = [];
  private recordsFilePath: string = '';
  private isLoaded: boolean = false;
  private isInitialized: boolean = false;
  private static readonly MAX_RECORDS: number = 200;

  private constructor() {}

  public static getInstance(): ErrorRecordManager {
    if (!ErrorRecordManager.instance) {
      ErrorRecordManager.instance = new ErrorRecordManager();
    }
    return ErrorRecordManager.instance;
  }

  public initialize(context: common.UIAbilityContext): void {
    try {
      const targetPath = `${context.filesDir}/error_records.json`;
      if (this.isInitialized && this.recordsFilePath === targetPath) {
        return;
      }

      this.context = context;
      this.recordsFilePath = targetPath;
      this.loadRecords();
      this.isInitialized = true;
      console.log(`[NGF] ${TAG}: 初始化完成，已加载 ${this.records.length} 条记录`);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: 初始化失败: ${msg}`);
    }
  }

  public addRuntimeError(
    tag: string,
    message: string,
    level: string,
    logFileName: string,
    category: ErrorCategory = ErrorCategory.UNKNOWN
  ): string {
    const now = Date.now();
    const record: ErrorRecord = {
      id: `rt_${now}_${Math.floor(Math.random() * 10000)}`,
      source: ErrorSource.RUNTIME_ERROR,
      category: category,
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

  public addCrashRecord(
    errorMessage: string,
    stackTrace: string,
    logFileName: string,
    category: ErrorCategory = ErrorCategory.SYSTEM
  ): void {
    const now = Date.now();
    const record: ErrorRecord = {
      id: `cr_${now}_${Math.floor(Math.random() * 10000)}`,
      source: ErrorSource.CRASH,
      category: category,
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

  public addNetworkError(
    tag: string,
    message: string,
    level: string,
    logFileName: string,
    category: ErrorCategory = ErrorCategory.NETWORK
  ): string {
    const now = Date.now();
    const record: ErrorRecord = {
      id: `net_${now}_${Math.floor(Math.random() * 10000)}`,
      source: ErrorSource.NETWORK_ERROR,
      category: category,
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
    while (this.records.length > ErrorRecordManager.MAX_RECORDS) {
      this.records.shift();
    }
    this.saveRecords();
  }

  public getAllRecords(): ErrorRecord[] {
    const result = this.records.slice();
    result.sort((a: ErrorRecord, b: ErrorRecord) => b.timestamp - a.timestamp);
    return result;
  }

  public getRecordsBySource(source: ErrorSource): ErrorRecord[] {
    return this.getAllRecords().filter((r: ErrorRecord) => r.source === source);
  }

  public getSummary(): ErrorSummary {
    const tagMap = new Map<string, number>();
    const categoryMap = new Map<ErrorCategory, number>();
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

      const curTag = tagMap.get(r.tag) || 0;
      tagMap.set(r.tag, curTag + 1);

      const category = this.normalizeCategory(r.category, r.source);
      const curCat = categoryMap.get(category) || 0;
      categoryMap.set(category, curCat + 1);
    }

    const topTags: TagCount[] = [];
    tagMap.forEach((count: number, tag: string) => {
      topTags.push({ tag, count });
    });
    topTags.sort((a: TagCount, b: TagCount) => b.count - a.count);

    const categoryCounts: CategoryCount[] = [];
    categoryMap.forEach((count: number, category: ErrorCategory) => {
      categoryCounts.push({ category, count });
    });
    categoryCounts.sort((a: CategoryCount, b: CategoryCount) => b.count - a.count);

    return {
      total: this.records.length,
      runtimeErrors: runtimeCount,
      crashes: crashCount,
      networkErrors: networkCount,
      categoryCounts: categoryCounts,
      topTags: topTags.slice(0, 10),
      firstTime: firstTime === Number.MAX_SAFE_INTEGER ? 0 : firstTime,
      lastTime: lastTime
    };
  }

  public deleteRecord(id: string): void {
    this.records = this.records.filter((r: ErrorRecord) => r.id !== id);
    this.saveRecords();
  }

  public clearAll(): void {
    this.records = [];
    this.saveRecords();
  }

  public updateRecordLogFileName(id: string, fileName: string): void {
    for (let i = this.records.length - 1; i >= 0; i--) {
      if (this.records[i].id === id) {
        this.records[i].logFileName = fileName;
        this.saveRecords();
        return;
      }
    }
  }

  public exportSingleRecord(record: ErrorRecord): string {
    const sections: string[] = [];
    const category = this.normalizeCategory(record.category, record.source);

    sections.push('========================');
    sections.push('漫匣 错误详情报告');
    sections.push('========================');
    sections.push('');
    sections.push(`错误ID: ${record.id}`);
    sections.push(`来源: ${record.source}`);
    sections.push(`分类: ${this.getCategoryLabel(category)} (${category})`);
    sections.push(`时间: ${record.timeStr}`);
    sections.push(`级别: ${record.level}`);
    sections.push(`模块: ${record.tag}`);
    sections.push(`设备: ${record.deviceModel}`);
    sections.push(`系统: ${record.osVersion}`);
    sections.push('');
    sections.push('错误消息:');
    sections.push(record.message);
    sections.push('');
    if (record.stackTrace) {
      sections.push('堆栈信息:');
      sections.push(record.stackTrace);
      sections.push('');
    }
    if (record.logFileName) {
      sections.push(`关联日志文件: ${record.logFileName}`);
    }

    return sections.join('\n');
  }

  public exportMultipleRecords(records: ErrorRecord[]): string {
    const sorted = records.slice().sort((a: ErrorRecord, b: ErrorRecord) => a.timestamp - b.timestamp);
    const sections: string[] = [];

    sections.push('========================');
    sections.push('漫匣 错误合并导出报告');
    sections.push('========================');
    sections.push(`导出时间: ${this.formatDateTime(Date.now())}`);
    sections.push(`错误总数: ${sorted.length}`);
    sections.push('');
    sections.push(`设备: ${this.getDeviceModel()}`);
    sections.push(`系统: ${this.getOsVersion()}`);
    sections.push('');

    let runtimeCount = 0;
    let crashCount = 0;
    let networkCount = 0;
    const categoryMap = new Map<ErrorCategory, number>();
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

      const category = this.normalizeCategory(r.category, r.source);
      const catCur = categoryMap.get(category) || 0;
      categoryMap.set(category, catCur + 1);

      const tagCur = tagSet.get(r.tag) || 0;
      tagSet.set(r.tag, tagCur + 1);
    }

    sections.push('统计摘要:');
    sections.push(`运行时错误: ${runtimeCount}`);
    sections.push(`网络错误: ${networkCount}`);
    sections.push(`闪退记录: ${crashCount}`);
    sections.push(`时间跨度: ${sorted.length > 0 ? sorted[0].timeStr : '-'} ~ ${sorted.length > 0 ? sorted[sorted.length - 1].timeStr : '-'}`);
    sections.push('');

    sections.push('分类分布:');
    const categoryCounts: CategoryCount[] = [];
    categoryMap.forEach((count: number, category: ErrorCategory) => {
      categoryCounts.push({ category, count });
    });
    categoryCounts.sort((a: CategoryCount, b: CategoryCount) => b.count - a.count);
    for (let i = 0; i < categoryCounts.length; i++) {
      sections.push(`- ${this.getCategoryLabel(categoryCounts[i].category)}: ${categoryCounts[i].count}`);
    }
    sections.push('');

    sections.push('涉及模块:');
    tagSet.forEach((count: number, tag: string) => {
      sections.push(`- ${tag}: ${count}`);
    });
    sections.push('');

    sections.push('错误详情列表:');
    sections.push('');

    for (let i = 0; i < sorted.length; i++) {
      const r = sorted[i];
      sections.push(`---- ${i + 1}/${sorted.length} ----`);
      sections.push(`ID: ${r.id}`);
      sections.push(`来源: ${r.source}`);
      sections.push(`分类: ${this.getCategoryLabel(this.normalizeCategory(r.category, r.source))}`);
      sections.push(`时间: ${r.timeStr}`);
      sections.push(`级别: ${r.level}`);
      sections.push(`模块: ${r.tag}`);
      sections.push(`消息: ${r.message}`);
      if (r.stackTrace) {
        sections.push('堆栈:');
        const stackLines = r.stackTrace.split('\n');
        for (let j = 0; j < stackLines.length; j++) {
          sections.push(`  ${stackLines[j]}`);
        }
      }
      if (r.logFileName) {
        sections.push(`日志文件: ${r.logFileName}`);
      }
      sections.push('');
    }

    sections.push('报告结束');
    return sections.join('\n');
  }

  private loadRecords(): void {
    try {
      if (!this.recordsFilePath) {
        this.isLoaded = true;
        return;
      }

      const exists = fs.accessSync(this.recordsFilePath);
      if (!exists) {
        // 首次启动时文件不存在属于正常情况，保持内存中的已有记录
        this.isLoaded = true;
        return;
      }

      const file = fs.openSync(this.recordsFilePath, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(this.recordsFilePath);
      if (stat.size === 0) {
        fs.closeSync(file);
        if (this.records.length === 0) {
          this.records = [];
        }
        this.isLoaded = true;
        return;
      }

      const buf = new ArrayBuffer(Number(stat.size));
      fs.readSync(file.fd, buf);
      fs.closeSync(file);

      const decoder = new util.TextDecoder('utf-8');
      const jsonStr = decoder.decodeToString(new Uint8Array(buf));
      const parsed = JSON.parse(jsonStr) as Array<Partial<ErrorRecord>>;

      if (!Array.isArray(parsed)) {
        if (this.records.length === 0) {
          this.records = [];
        }
        this.isLoaded = true;
        return;
      }

      const normalized: ErrorRecord[] = [];
      let needsRewrite = false;

      for (let i = 0; i < parsed.length; i++) {
        const before = parsed[i];
        const record = this.normalizeRecord(before);
        if (record) {
          normalized.push(record);
          if (before.category !== record.category || before.source !== record.source) {
            needsRewrite = true;
          }
        } else {
          needsRewrite = true;
        }
      }

      this.records = normalized;
      this.isLoaded = true;

      if (needsRewrite) {
        this.saveRecords();
      }
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      if (msg.indexOf('No such file or directory') >= 0) {
        this.isLoaded = true;
        return;
      }
      console.error(`[NGF] ${TAG}: 加载错误记录失败: ${msg}`);
      this.records = [];
      this.isLoaded = true;
    }
  }

  private normalizeRecord(raw: Partial<ErrorRecord>): ErrorRecord | null {
    if (!raw) {
      return null;
    }

    const source = this.normalizeSource(raw.source);
    const timestamp = typeof raw.timestamp === 'number' && !Number.isNaN(raw.timestamp)
      ? raw.timestamp
      : Date.now();

    const id = typeof raw.id === 'string' && raw.id.length > 0
      ? raw.id
      : `${source}_${timestamp}_${Math.floor(Math.random() * 10000)}`;

    const category = this.normalizeCategory(raw.category, source);

    return {
      id: id,
      source: source,
      category: category,
      timestamp: timestamp,
      timeStr: typeof raw.timeStr === 'string' && raw.timeStr.length > 0 ? raw.timeStr : this.formatDateTime(timestamp),
      tag: typeof raw.tag === 'string' ? raw.tag : 'UNKNOWN',
      message: typeof raw.message === 'string' ? raw.message : '',
      stackTrace: typeof raw.stackTrace === 'string' ? raw.stackTrace : '',
      level: typeof raw.level === 'string' ? raw.level : 'ERROR',
      logFileName: typeof raw.logFileName === 'string' ? raw.logFileName : '',
      deviceModel: typeof raw.deviceModel === 'string' && raw.deviceModel.length > 0 ? raw.deviceModel : this.getDeviceModel(),
      osVersion: typeof raw.osVersion === 'string' && raw.osVersion.length > 0 ? raw.osVersion : this.getOsVersion()
    };
  }

  private normalizeSource(source: ErrorSource | string | undefined): ErrorSource {
    if (source === ErrorSource.CRASH || source === ErrorSource.NETWORK_ERROR || source === ErrorSource.RUNTIME_ERROR) {
      return source;
    }

    if (source === 'crash') {
      return ErrorSource.CRASH;
    }
    if (source === 'network') {
      return ErrorSource.NETWORK_ERROR;
    }

    return ErrorSource.RUNTIME_ERROR;
  }

  private normalizeCategory(category: ErrorCategory | string | undefined, source: ErrorSource): ErrorCategory {
    switch (category) {
      case ErrorCategory.NETWORK:
      case ErrorCategory.DOWNLOAD:
      case ErrorCategory.STORAGE:
      case ErrorCategory.DATA:
      case ErrorCategory.PARSER:
      case ErrorCategory.SOURCE:
      case ErrorCategory.WEBVIEW:
      case ErrorCategory.AUTH:
      case ErrorCategory.SYNC:
      case ErrorCategory.UI:
      case ErrorCategory.SYSTEM:
      case ErrorCategory.UNKNOWN:
        return category;
      default:
        return this.getDefaultCategoryForSource(source);
    }
  }

  private getDefaultCategoryForSource(source: ErrorSource): ErrorCategory {
    if (source === ErrorSource.NETWORK_ERROR) {
      return ErrorCategory.NETWORK;
    }
    if (source === ErrorSource.CRASH) {
      return ErrorCategory.SYSTEM;
    }
    return ErrorCategory.UNKNOWN;
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

  private getCategoryLabel(category: ErrorCategory): string {
    switch (category) {
      case ErrorCategory.NETWORK: return '网络';
      case ErrorCategory.DOWNLOAD: return '下载';
      case ErrorCategory.STORAGE: return '存储';
      case ErrorCategory.DATA: return '数据';
      case ErrorCategory.PARSER: return '解析';
      case ErrorCategory.SOURCE: return '书源/图源';
      case ErrorCategory.WEBVIEW: return 'WebView';
      case ErrorCategory.AUTH: return '认证登录';
      case ErrorCategory.SYNC: return '同步备份';
      case ErrorCategory.UI: return '界面交互';
      case ErrorCategory.SYSTEM: return '系统生命周期';
      default: return '未分类';
    }
  }
}

export function getErrorRecordManager(): ErrorRecordManager {
  return ErrorRecordManager.getInstance();
}
