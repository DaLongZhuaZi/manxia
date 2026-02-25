// 文件路径: entry/src/main/ets/Framework/Debug/ErrorMonitorService.ets
/**
 * 错误监控服务
 * 通过 LogCollector 监听器实时捕捉所有 ERROR 及以上级别的程序性日志，
 * 排除网络相关错误，在出现错误时通过 AppStorage 事件通知页面弹窗，
 * 并自动将错误附近的 500 行日志导出为 txt 文件。
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { LogLevel } from '../../Utils/Logger';
import { LogCollector, LogEntry } from './LogCollector';
import { DownloadDirManager } from '../Storage/DownloadDirManager';
import { ErrorRecordManager } from './ErrorRecordManager';
import { deviceInfo } from '@kit.BasicServicesKit';

const TAG = 'ErrorMonitorService';

/**
 * 网络相关错误的关键词列表（匹配到任意一个即视为网络错误，将被排除）
 */
const NETWORK_ERROR_KEYWORDS: string[] = [
  '无法连接', '无法获取', '连接超时', '连接失败', '连接被拒绝',
  '网络错误', '网络异常', '网络不可用', '网络请求失败', '网络超时',
  'NETWORK', 'network error', 'connection refused', 'connection reset',
  'connection timeout', 'connect timeout', 'ETIMEDOUT', 'ECONNREFUSED',
  'ECONNRESET', 'ENOTFOUND', 'EHOSTUNREACH', 'fetch failed',
  'request timeout', 'socket timeout', 'DNS resolution',
  '请求超时', '请求失败', '服务器无响应', '服务器错误',
  'ERR_CONNECTION', 'ERR_NETWORK', 'ERR_INTERNET',
  'SSL error', 'TLS error', 'certificate',
  'WebSocket', 'websocket', 'http error', 'HTTP error',
  '代理', 'proxy error', 'SOCKS',
  '无法解析', '域名解析', 'Unable to resolve',
  'status code: 5', 'status code: 4',  // 4xx, 5xx HTTP错误
  'Response timeout', 'Request aborted'
];

/**
 * 错误监控服务
 */
export class ErrorMonitorService {
  private static instance: ErrorMonitorService;
  private context: common.UIAbilityContext | null = null;
  private logCollector: LogCollector = LogCollector.getInstance();
  private isStarted: boolean = false;
  private errorLogsDir: string = '';
  private logListener: ((entry: LogEntry) => void) | null = null;

  // 防抖控制：同类错误3秒内只处理一次
  private lastErrorTime: number = 0;
  private lastErrorMessage: string = '';
  private readonly DEBOUNCE_INTERVAL: number = 3000;

  // 错误计数器（用于文件命名）
  private errorCounter: number = 0;

  // 排除的tag（这些标签的ERROR通常不是程序性错误）
  private static readonly EXCLUDED_TAGS: string[] = [
    'ErrorMonitorService',   // 自身产生的日志避免循环
    'CrashRecorderService',  // 崩溃服务自身的日志
  ];

  private constructor() {}

  public static getInstance(): ErrorMonitorService {
    if (!ErrorMonitorService.instance) {
      ErrorMonitorService.instance = new ErrorMonitorService();
    }
    return ErrorMonitorService.instance;
  }

  /**
   * 启动错误监控服务
   * 应在日志系统完全就绪后延迟调用
   */
  public start(context: common.UIAbilityContext): void {
    if (this.isStarted) {
      console.log(`[NGF] ${TAG}: 错误监控已启动，跳过`);
      return;
    }

    try {
      this.context = context;
      this.errorLogsDir = `${context.filesDir}/error_logs`;

      // 确保错误日志目录存在
      this.ensureErrorLogsDir();

      // 注册 LogCollector 监听器
      this.logListener = (entry: LogEntry): void => {
        this.onLogEntry(entry);
      };
      this.logCollector.addListener(this.logListener);

      this.isStarted = true;
      console.log(`[NGF] ${TAG}: ✅ 错误监控服务已启动`);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: ❌ 启动失败: ${msg}`);
    }
  }

  /**
   * 确保错误日志目录存在
   */
  private ensureErrorLogsDir(): void {
    try {
      fs.accessSync(this.errorLogsDir);
    } catch {
      fs.mkdirSync(this.errorLogsDir, true);
    }
  }

  /**
   * 日志条目回调 —— 核心监控逻辑
   */
  private onLogEntry(entry: LogEntry): void {
    // 仅处理 ERROR 及以上级别
    if (entry.level < LogLevel.ERROR) {
      return;
    }

    // 排除自身标签，避免循环
    if (ErrorMonitorService.EXCLUDED_TAGS.indexOf(entry.tag) >= 0) {
      return;
    }

    // 判断是否为网络相关错误（不再跳过，而是标记后统一处理）
    const isNetwork = this.isNetworkError(entry);

    // 防抖：同类错误3秒内只处理一次
    const now = Date.now();
    if (entry.message === this.lastErrorMessage &&
        (now - this.lastErrorTime) < this.DEBOUNCE_INTERVAL) {
      return;
    }
    this.lastErrorTime = now;
    this.lastErrorMessage = entry.message;

    // 处理错误（网络错误和程序性错误均记录）
    this.handleProgramError(entry, isNetwork);
  }

  /**
   * 判断是否为网络相关错误
   */
  private isNetworkError(entry: LogEntry): boolean {
    const fullText = `${entry.tag} ${entry.message} ${entry.args.join(' ')}`.toLowerCase();

    for (let i = 0; i < NETWORK_ERROR_KEYWORDS.length; i++) {
      if (fullText.includes(NETWORK_ERROR_KEYWORDS[i].toLowerCase())) {
        return true;
      }
    }

    return false;
  }

  /**
   * 处理程序性错误
   */
  private handleProgramError(entry: LogEntry, isNetworkError: boolean): void {
    // 1. 立即向 ErrorRecordManager 注册记录（确保错误一定被记录）
    let recordId = '';
    try {
      const levelName = this.getLevelName(entry.level);
      if (isNetworkError) {
        recordId = ErrorRecordManager.getInstance().addNetworkError(entry.tag, entry.message, levelName, '');
      } else {
        recordId = ErrorRecordManager.getInstance().addRuntimeError(entry.tag, entry.message, levelName, '');
      }
    } catch (regError) {
      const msg = regError instanceof Error ? regError.message : String(regError);
      console.error(`[NGF] ${TAG}: 注册错误记录失败: ${msg}`);
    }

    // 网络错误仅记录，不弹窗、不导出日志文件
    if (isNetworkError) {
      return;
    }

    try {
      // 2. 通过 AppStorage 通知页面弹窗
      this.notifyErrorDialog(entry);

      // 3. 异步导出错误附近的500行日志
      this.exportErrorContext(entry, recordId);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: 处理错误时发生异常: ${msg}`);
    }
  }

  /**
   * 通知页面显示错误弹窗
   * 通过 AppStorage 发布错误事件，由页面层的错误弹窗组件消费
   */
  private notifyErrorDialog(entry: LogEntry): void {
    try {
      const errorInfo: string = JSON.stringify({
        timestamp: entry.timestamp,
        tag: entry.tag,
        message: entry.message,
        level: entry.level,
        time: this.formatDateTime(entry.timestamp)
      });

      // 设置错误信息到 AppStorage，页面可监听此变化
      AppStorage.setOrCreate('latestProgramError', errorInfo);
      // 递增错误计数触发 UI 更新
      const currentCount: number = AppStorage.get<number>('programErrorCount') || 0;
      AppStorage.setOrCreate('programErrorCount', currentCount + 1);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: 通知错误弹窗失败: ${msg}`);
    }
  }

  /**
   * 导出错误附近的500行日志
   * 以错误所在位置为中心，前250行 + 后250行（取可用范围）
   */
  private exportErrorContext(entry: LogEntry, recordId: string = ''): void {
    try {
      const allLogs = this.logCollector.getAllLogs();
      if (allLogs.length === 0) {
        return;
      }

      // 找到错误条目在日志中的位置
      let errorIndex = -1;
      for (let i = allLogs.length - 1; i >= 0; i--) {
        if (allLogs[i].id === entry.id) {
          errorIndex = i;
          break;
        }
      }

      if (errorIndex < 0) {
        // 如果找不到精确匹配，取最后一条
        errorIndex = allLogs.length - 1;
      }

      // 计算500行上下文范围
      const contextSize = 500;
      const halfContext = Math.floor(contextSize / 2); // 250
      let startIndex = Math.max(0, errorIndex - halfContext);
      let endIndex = Math.min(allLogs.length - 1, errorIndex + halfContext);

      // 如果前面不够250行，多取后面的
      if (errorIndex - startIndex < halfContext) {
        endIndex = Math.min(allLogs.length - 1, endIndex + (halfContext - (errorIndex - startIndex)));
      }
      // 如果后面不够250行，多取前面的
      if (endIndex - errorIndex < halfContext) {
        startIndex = Math.max(0, startIndex - (halfContext - (endIndex - errorIndex)));
      }

      const contextLogs: LogEntry[] = allLogs.slice(startIndex, endIndex + 1);

      // 构建导出内容
      const content = this.buildErrorReport(entry, contextLogs, errorIndex - startIndex);

      // 导出文件
      this.writeErrorLogFile(entry, content, recordId);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: 导出错误上下文失败: ${msg}`);
    }
  }

  /**
   * 构建错误报告内容
   */
  private buildErrorReport(
    errorEntry: LogEntry,
    contextLogs: LogEntry[],
    errorPositionInContext: number
  ): string {
    const sections: string[] = [];

    sections.push('════════════════════════════════════════════════════════════');
    sections.push('  漫匣 APP 错误报告（自动导出）');
    sections.push('════════════════════════════════════════════════════════════');
    sections.push('');

    // 错误摘要
    sections.push('▶ 错误摘要');
    sections.push(`  时间: ${this.formatDateTime(errorEntry.timestamp)}`);
    sections.push(`  标签: ${errorEntry.tag}`);
    sections.push(`  级别: ${this.getLevelName(errorEntry.level)}`);
    sections.push(`  消息: ${errorEntry.message}`);
    if (errorEntry.args && errorEntry.args.length > 0) {
      sections.push(`  参数: ${errorEntry.args.join(' ')}`);
    }
    sections.push('');

    // 设备信息
    sections.push('▶ 设备信息');
    try {
      sections.push(`  型号: ${deviceInfo.productModel || '未知'} (${deviceInfo.brand || '未知'})`);
      sections.push(`  系统: ${deviceInfo.osFullName || '未知'}`);
    } catch {
      sections.push('  设备信息获取失败');
    }
    sections.push('');

    // 上下文日志
    sections.push('════════════════════════════════════════════════════════════');
    sections.push(`▶ 错误上下文日志（共 ${contextLogs.length} 条，错误位于第 ${errorPositionInContext + 1} 条）`);
    sections.push('════════════════════════════════════════════════════════════');
    sections.push('');

    for (let i = 0; i < contextLogs.length; i++) {
      const log = contextLogs[i];
      const time = this.formatDateTime(log.timestamp);
      const levelName = this.getLevelName(log.level);
      const marker = (i === errorPositionInContext) ? ' ★★★ ' : '     ';
      let line = `${marker}[${time}] [${levelName}] [${log.tag}] ${log.message}`;
      if (log.args && log.args.length > 0) {
        line += ` ${log.args.join(' ')}`;
      }
      if (log.details) {
        line += `\n       详情: ${log.details}`;
      }
      sections.push(line);
    }

    return sections.join('\n');
  }

  /**
   * 写入错误日志文件
   * 默认先写入沙箱 error_logs/，再尝试复制到 Download
   */
  private writeErrorLogFile(entry: LogEntry, content: string, recordId: string = ''): void {
    try {
      this.errorCounter++;
      const dateStr = this.formatDateTime(entry.timestamp);
      const safeDate = dateStr.replace(/[:/]/g, '-').replace(/\s/g, '_').replace(/\./g, '-');
      const fileName = `error_${safeDate}_${this.errorCounter}.txt`;

      // 1. 始终先写入沙箱
      this.ensureErrorLogsDir();
      const sandboxPath = `${this.errorLogsDir}/${fileName}`;
      const file = fs.openSync(sandboxPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
      console.log(`[NGF] ${TAG}: ✅ 错误日志已保存到沙箱: ${fileName}`);

      // 2. 尝试复制到 Download 目录
      this.tryCopyToDownload(sandboxPath, fileName);

      // 3. 更新 ErrorRecordManager 中的日志文件名
      if (recordId) {
        try {
          ErrorRecordManager.getInstance().updateRecordLogFileName(recordId, fileName);
        } catch {
          // 更新失败不影响主流程
        }
      }

      // 4. 清理旧的错误日志（沙箱中保留最近20份）
      this.cleanOldErrorLogs();
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: 写入错误日志失败: ${msg}`);
    }
  }

  /**
   * 尝试将沙箱中的错误日志复制到 Download 目录
   */
  private tryCopyToDownload(sourcePath: string, fileName: string): void {
    try {
      const downloadDirManager = DownloadDirManager.getInstance();
      const logsDir = downloadDirManager.ensureDirectory('logs');
      const targetPath = `${logsDir}/${fileName}`;
      fs.copyFileSync(sourcePath, targetPath);
      console.log(`[NGF] ${TAG}: 错误日志已复制到 Download 目录`);
    } catch {
      // 复制失败不影响主流程
    }
  }

  /**
   * 清理旧的错误日志（保留最近20份）
   */
  private cleanOldErrorLogs(): void {
    try {
      const files = fs.listFileSync(this.errorLogsDir);
      const errorFiles = files.filter((f: string) => f.startsWith('error_') && f.endsWith('.txt'));

      if (errorFiles.length <= 20) {
        return;
      }

      errorFiles.sort();
      const toDelete = errorFiles.slice(0, errorFiles.length - 20);
      for (const fileName of toDelete) {
        try {
          fs.unlinkSync(`${this.errorLogsDir}/${fileName}`);
        } catch {
          // 忽略
        }
      }
    } catch {
      // 清理失败不影响主流程
    }
  }

  /**
   * 停止错误监控
   */
  public stop(): void {
    if (this.logListener) {
      this.logCollector.removeListener(this.logListener);
      this.logListener = null;
    }
    this.isStarted = false;
    console.log(`[NGF] ${TAG}: 错误监控服务已停止`);
  }

  /**
   * 检查是否已启动
   */
  public isRunning(): boolean {
    return this.isStarted;
  }

  /**
   * 获取错误日志目录
   */
  public getErrorLogsDir(): string {
    return this.errorLogsDir;
  }

  /**
   * 格式化日期时间
   */
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

  /**
   * 获取日志级别名称
   */
  private getLevelName(level: LogLevel): string {
    switch (level) {
      case LogLevel.DEBUG: return 'DEBUG';
      case LogLevel.INFO: return 'INFO';
      case LogLevel.WARN: return 'WARN';
      case LogLevel.ERROR: return 'ERROR';
      case LogLevel.FATAL: return 'FATAL';
      default: return 'UNKNOWN';
    }
  }
}

// 导出单例获取函数
export function getErrorMonitorService(): ErrorMonitorService {
  return ErrorMonitorService.getInstance();
}
