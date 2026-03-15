// 文件路径: entry/src/main/ets/Framework/Debug/CrashRecorderService.ets
/**
 * 闪退记录服务
 * 通过 HarmonyOS errorManager 捕获未处理异常（JS Crash），
 * 在崩溃前保存完整日志快照；下次启动时通过 faultLogger 查询历史崩溃信息。
 * 实现类似 Windows 蓝屏记录的效果。
 */

import { errorManager } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { LogLevel } from '../../Utils/Logger';
import { LogCollector, LogEntry } from './LogCollector';
import { DownloadDirManager } from '../Storage/DownloadDirManager';
import { ErrorRecordManager } from './ErrorRecordManager';
import { deviceInfo } from '@kit.BasicServicesKit';

const TAG = 'CrashRecorderService';

/**
 * 崩溃记录信息
 */
export interface CrashRecord {
  crashTime: number;           // 崩溃时间戳
  crashTimeStr: string;        // 崩溃时间字符串
  errorMessage: string;        // 异常消息
  stackTrace: string;          // 堆栈信息
  logSnapshot: string;         // 崩溃前的日志快照文件路径
  logFileName: string;         // 崩溃日志文件名
  deviceInfo: string;          // 设备信息
  isFromFaultLogger: boolean;  // 是否来自 faultLogger（上次崩溃）
}

/**
 * errorManager 回调接口
 */
interface ErrorObserver {
  onUnhandledException: (errMsg: string) => void;
  onException?: (errObj: Error) => void;
}

/**
 * 闪退记录服务
 */
export class CrashRecorderService {
  private static instance: CrashRecorderService;
  private context: common.UIAbilityContext | null = null;
  private errorObserverId: number = -1;
  private isRegistered: boolean = false;
  private hasCheckedPreviousCrash: boolean = false;
  private crashLogsDir: string = '';
  private logCollector: LogCollector = LogCollector.getInstance();
  private isSaving: boolean = false; // 防止重复保存

  private constructor() {}

  public static getInstance(): CrashRecorderService {
    if (!CrashRecorderService.instance) {
      CrashRecorderService.instance = new CrashRecorderService();
    }
    return CrashRecorderService.instance;
  }

  /**
   * 初始化闪退记录服务
   * 应在 EntryAbility 的 onCreate 中尽早调用
   */
  public initialize(context: common.UIAbilityContext): void {
    try {
      this.context = context;
      this.crashLogsDir = `${context.filesDir}/crash_logs`;

      // 确保崩溃日志目录存在
      this.ensureCrashLogsDir();

      // 注册全局异常监听
      this.registerErrorObserver();

      // 仅在首次初始化时检查上次崩溃记录，避免重复读取/重复日志
      if (!this.hasCheckedPreviousCrash) {
        this.checkPreviousCrashLogs();
        this.hasCheckedPreviousCrash = true;
      }

      console.log(`[NGF] ${TAG}: 闪退记录服务初始化完成`);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: 初始化失败: ${msg}`);
    }
  }

  /**
   * 确保崩溃日志目录存在
   */
  private ensureCrashLogsDir(): void {
    if (!this.crashLogsDir) {
      return;
    }

    try {
      const exists = fs.accessSync(this.crashLogsDir);
      if (exists) {
        return;
      }
    } catch (_) {
      // ignore and try to create
    }

    try {
      fs.mkdirSync(this.crashLogsDir, true);
      console.log(`[NGF] ${TAG}: 崩溃日志目录已创建: ${this.crashLogsDir}`);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: 创建崩溃日志目录失败: ${msg}`);
    }
  }

  /**
   * 注册全局异常监听器
   * 注册后应用崩溃时进程不会立即退出，可以执行日志保存操作
   */
  private registerErrorObserver(): void {
    if (this.isRegistered) {
      console.log(`[NGF] ${TAG}: 异常监听器已注册，跳过`);
      return;
    }

    try {
      const observer: ErrorObserver = {
        onUnhandledException: (errMsg: string): void => {
          this.handleCrash(errMsg, '');
        },
        onException: (errObj: Error): void => {
          const message: string = errObj.message || 'Unknown Error';
          const stack: string = errObj.stack || '';
          this.handleCrash(message, stack);
        }
      };

      this.errorObserverId = errorManager.on('error', observer);
      this.isRegistered = true;
      console.log(`[NGF] ${TAG}: ✅ 全局异常监听器注册成功 (observerId: ${this.errorObserverId})`);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: ❌ 注册异常监听器失败: ${msg}`);
    }
  }

  /**
   * 处理崩溃事件
   * 在崩溃前同步保存日志快照
   */
  private handleCrash(errorMessage: string, stackTrace: string): void {
    // 防止重复保存（短时间内可能触发多次）
    if (this.isSaving) {
      return;
    }
    this.isSaving = true;

    try {
      this.ensureCrashLogsDir();
      console.error(`[NGF] ${TAG}: 🚨 捕获到未处理异常: ${errorMessage}`);

      const now = Date.now();
      const dateStr = this.formatDateTime(now);
      const safeDate = dateStr.replace(/[:/\\s]/g, '-').replace(/\s/g, '_');
      const fileName = `crash_${safeDate}.txt`;
      const filePath = `${this.crashLogsDir}/${fileName}`;

      // 收集所有日志
      const allLogs = this.logCollector.getAllLogs();

      // 构建崩溃报告内容
      const content = this.buildCrashReport(now, dateStr, errorMessage, stackTrace, allLogs);

      // 同步写入文件（崩溃场景下必须用同步操作）
      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);

      console.error(`[NGF] ${TAG}: ✅ 崩溃日志已保存: ${filePath}`);

      // 尝试复制到 Download 目录
      this.tryCopyCrashToDownload(filePath, fileName);

      // 向 ErrorRecordManager 注册结构化记录
      try {
        ErrorRecordManager.getInstance().addCrashRecord(errorMessage, stackTrace, fileName);
      } catch {
        // 注册失败不影响主流程
      }

      // 同时保存崩溃摘要信息（供下次启动快速读取）
      this.saveCrashSummary(now, errorMessage, stackTrace, fileName);
    } catch (saveError) {
      const msg = saveError instanceof Error ? saveError.message : String(saveError);
      console.error(`[NGF] ${TAG}: ❌ 保存崩溃日志失败: ${msg}`);
    } finally {
      this.isSaving = false;
    }
  }

  /**
   * 构建崩溃报告内容
   */
  private buildCrashReport(
    timestamp: number,
    dateStr: string,
    errorMessage: string,
    stackTrace: string,
    logs: LogEntry[]
  ): string {
    const sections: string[] = [];

    // 标题
    sections.push('╔══════════════════════════════════════════════════════════════╗');
    sections.push('║                    漫匣 APP 闪退报告                        ║');
    sections.push('╚══════════════════════════════════════════════════════════════╝');
    sections.push('');

    // 崩溃信息
    sections.push('【崩溃时间】');
    sections.push(`  ${dateStr}`);
    sections.push('');

    // 设备信息
    sections.push('【设备信息】');
    try {
      sections.push(`  设备类型: ${deviceInfo.deviceType || '未知'}`);
      sections.push(`  品牌: ${deviceInfo.brand || '未知'}`);
      sections.push(`  型号: ${deviceInfo.productModel || '未知'}`);
      sections.push(`  系统版本: ${deviceInfo.osFullName || '未知'}`);
      sections.push(`  SDK版本: ${deviceInfo.sdkApiVersion || '未知'}`);
    } catch {
      sections.push('  设备信息获取失败');
    }
    sections.push('');

    // 异常信息
    sections.push('【异常信息】');
    sections.push(`  ${errorMessage}`);
    sections.push('');

    // 堆栈信息
    if (stackTrace) {
      sections.push('【堆栈信息】');
      sections.push(stackTrace);
      sections.push('');
    }

    // 崩溃前的完整日志
    sections.push('═'.repeat(60));
    sections.push(`【崩溃前日志快照（共 ${logs.length} 条）】`);
    sections.push('═'.repeat(60));
    sections.push('');

    for (let i = 0; i < logs.length; i++) {
      const log = logs[i];
      const time = this.formatDateTime(log.timestamp);
      const levelName = this.getLevelName(log.level);
      let line = `[${time}] [${levelName}] [${log.tag}] ${log.message}`;
      if (log.args && log.args.length > 0) {
        line += ` ${log.args.join(' ')}`;
      }
      if (log.details) {
        line += `\n  详情: ${log.details}`;
      }
      sections.push(line);
    }

    return sections.join('\n');
  }

  /**
   * 保存崩溃摘要（供下次启动快速读取）
   */
  private saveCrashSummary(
    timestamp: number,
    errorMessage: string,
    stackTrace: string,
    logFileName: string
  ): void {
    try {
      this.ensureCrashLogsDir();
      const summaryPath = `${this.crashLogsDir}/last_crash_summary.json`;
      const summary: string = JSON.stringify({
        crashTime: timestamp,
        crashTimeStr: this.formatDateTime(timestamp),
        errorMessage: errorMessage,
        stackTrace: stackTrace,
        logFileName: logFileName
      });

      const file = fs.openSync(summaryPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, summary);
      fs.closeSync(file);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: 保存崩溃摘要失败: ${msg}`);
    }
  }

  /**
   * 检查上次崩溃记录
   * 在启动时调用，如果存在崩溃记录则通过 AppStorage 标记
   */
  private checkPreviousCrashLogs(): void {
    try {
      this.ensureCrashLogsDir();
      const summaryPath = `${this.crashLogsDir}/last_crash_summary.json`;
      try {
        const exists = fs.accessSync(summaryPath);
        if (!exists) {
          console.log(`[NGF] ${TAG}: 未检测到上次崩溃记录`);
          return;
        }
      } catch (_) {
        // 没有崩溃摘要文件，说明上次正常退出
        console.log(`[NGF] ${TAG}: 未检测到上次崩溃记录`);
        return;
      }

      // 读取崩溃摘要
      const file = fs.openSync(summaryPath, fs.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(8192);
      const readLen = fs.readSync(file.fd, buf);
      fs.closeSync(file);

      const decoder = new util.TextDecoder('utf-8');
      const summaryStr = decoder.decodeToString(new Uint8Array(buf, 0, readLen));
      const summary = JSON.parse(summaryStr) as CrashRecord;

      console.log(`[NGF] ${TAG}: ⚠️ 检测到上次崩溃记录: ${summary.crashTimeStr}`);
      console.log(`[NGF] ${TAG}: 崩溃原因: ${summary.errorMessage}`);

      // 通过 AppStorage 标记，供页面展示
      AppStorage.setOrCreate('hasPreviousCrash', true);
      AppStorage.setOrCreate('previousCrashTime', summary.crashTimeStr || '');
      AppStorage.setOrCreate('previousCrashMessage', summary.errorMessage || '');
      AppStorage.setOrCreate('previousCrashStack', summary.stackTrace || '');
      AppStorage.setOrCreate('previousCrashLogFile', summary.logFileName || '');

      // 删除摘要文件（已读取，避免重复提示）
      fs.unlinkSync(summaryPath);
      console.log(`[NGF] ${TAG}: 崩溃摘要已读取并清除`);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      if (msg.indexOf('No such file or directory') >= 0) {
        console.log(`[NGF] ${TAG}: 未检测到上次崩溃记录`);
        return;
      }
      console.error(`[NGF] ${TAG}: 检查崩溃记录失败: ${msg}`);
    }
  }

  /**
   * 获取崩溃日志目录路径
   */
  public getCrashLogsDir(): string {
    return this.crashLogsDir;
  }

  /**
   * 获取所有崩溃日志文件列表
   */
  public getCrashLogFiles(): string[] {
    try {
      if (!this.crashLogsDir) {
        return [];
      }
      const exists = fs.accessSync(this.crashLogsDir);
      if (!exists) {
        return [];
      }
      const files = fs.listFileSync(this.crashLogsDir);
      return files.filter((f: string) => f.startsWith('crash_') && f.endsWith('.txt'));
    } catch {
      return [];
    }
  }

  /**
   * 读取指定崩溃日志内容
   */
  public readCrashLog(fileName: string): string {
    try {
      const filePath = `${this.crashLogsDir}/${fileName}`;
      const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(filePath);
      const buf = new ArrayBuffer(Number(stat.size));
      fs.readSync(file.fd, buf);
      fs.closeSync(file);

      const decoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(new Uint8Array(buf));
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      return `读取崩溃日志失败: ${msg}`;
    }
  }

  /**
   * 清理旧的崩溃日志（保留最近10份）
   */
  public cleanOldCrashLogs(): void {
    try {
      const files = this.getCrashLogFiles();
      if (files.length <= 10) {
        return;
      }

      // 按文件名排序（包含时间戳，自然排序即为时间排序）
      files.sort();
      const toDelete = files.slice(0, files.length - 10);
      for (const fileName of toDelete) {
        try {
          fs.unlinkSync(`${this.crashLogsDir}/${fileName}`);
        } catch {
          // 忽略单个文件删除失败
        }
      }
      console.log(`[NGF] ${TAG}: 已清理 ${toDelete.length} 份旧崩溃日志`);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: 清理旧崩溃日志失败: ${msg}`);
    }
  }

  /**
   * 尝试将崩溃日志复制到 Download 目录
   */
  private tryCopyCrashToDownload(sourcePath: string, fileName: string): void {
    try {
      const downloadDirManager = DownloadDirManager.getInstance();
      if (!downloadDirManager.isReady()) {
        return;
      }
      const logsDir = downloadDirManager.ensureDirectory('logs');
      const targetPath = `${logsDir}/${fileName}`;
      fs.copyFileSync(sourcePath, targetPath);
      console.error(`[NGF] ${TAG}: 崩溃日志已复制到 Download 目录`);
    } catch {
      // 崩溃场景下复制失败不影响
    }
  }

  /**
   * 注销异常监听器
   */
  public dispose(): void {
    if (this.isRegistered && this.errorObserverId >= 0) {
      try {
        errorManager.off('error', this.errorObserverId);
        this.isRegistered = false;
        console.log(`[NGF] ${TAG}: 异常监听器已注销`);
      } catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        console.error(`[NGF] ${TAG}: 注销异常监听器失败: ${msg}`);
      }
    }
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
export function getCrashRecorderService(): CrashRecorderService {
  return CrashRecorderService.getInstance();
}
