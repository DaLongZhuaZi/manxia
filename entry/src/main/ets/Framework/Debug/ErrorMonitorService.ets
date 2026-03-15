// 文件路径: entry/src/main/ets/Framework/Debug/ErrorMonitorService.ets
/**
 * 错误监控服务
 * 通过 LogCollector 监听 ERROR/FATAL 级别日志，
 * 记录结构化错误并导出错误上下文日志。
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { LogLevel } from '../../Utils/Logger';
import { LogCollector, LogEntry } from './LogCollector';
import { DownloadDirManager } from '../Storage/DownloadDirManager';
import { ErrorCategory, ErrorRecordManager } from './ErrorRecordManager';
import { deviceInfo } from '@kit.BasicServicesKit';

const TAG = 'ErrorMonitorService';

const NETWORK_ERROR_KEYWORDS: string[] = [
  '网络错误', '网络异常', '网络不可用', '网络请求失败', '网络超时', '请求超时', '读取超时',
  '连接超时', '连接失败', '连接被拒绝', '连接重置', '连接中断', '主机不可达', 'DNS解析失败', 'DNS 解析失败',
  '无法连接', '无法解析', '域名解析', '服务不可达', '接口超时', '请求被中止', '远程主机强迫关闭',
  '服务不可用', '网关超时', '证书过期', '证书校验失败', '握手失败', '代理认证失败',
  'network', 'network error', 'request timeout', 'response timeout', 'connection timeout',
  'connect timeout', 'socket timeout', 'socket hang up', 'connection refused', 'connection reset',
  'unable to resolve host', 'unable to resolve', 'dns', 'enotfound', 'ehostunreach', 'enetunreach', 'econnrefused',
  'econnreset', 'etimedout', 'fetch failed', 'failed to fetch', 'http error', 'https error',
  'ssl error', 'tls error', 'ssl handshake', 'certificate', 'cert verify failed', 'certificate expired',
  'read timed out', 'write timed out', 'unknownhostexception', 'sslpeerunverifiedexception',
  'temporary failure in name resolution', 'name or service not known', 'remote host closed connection',
  'too many requests', 'service unavailable', 'gateway timeout', 'bad gateway',
  'websocket', 'ws connection', 'proxy error', 'socks', 'err_connection', 'err_network', 'err_internet',
  'status code: 4', 'status code: 5', 'http 4', 'http 5', 'http 429', 'http 502', 'http 503', 'http 504'
];

const NETWORK_TAG_HINTS: string[] = [
  'network', 'proxy', 'socket', 'dns', 'http', 'https', 'okhttp', 'axios', 'fetch', 'request',
  'httpclient', 'websocket', 'webdav'
];

interface ErrorCategoryRule {
  category: ErrorCategory;
  tagHints: string[];
  keywords: string[];
}

const CATEGORY_RULES: ErrorCategoryRule[] = [
  {
    category: ErrorCategory.DOWNLOAD,
    tagHints: [
      'downloadmanager', 'downloadsyncmanager', 'downloaddirmanager', 'mangadownloadmanager',
      'downloadpage', 'chapterdownload', 'downloadtask'
    ],
    keywords: [
      '下载失败', '下载任务', '下载队列', '下载目录', 'download failed', 'download task',
      'save download', 'resume download', 'range request', 'download queue'
    ]
  },
  {
    category: ErrorCategory.STORAGE,
    tagHints: ['storage', 'cache', 'diskcache', 'sandbox', 'backupmanager', 'sandboxmanager', 'cachemanager', 'fileio'],
    keywords: [
      'no such file or directory', 'enoent', 'eacces', 'enospc', 'read-only file system', 'not enough space',
      '磁盘', '目录', '文件', '存储', '权限', '路径不存在', '创建目录失败', '文件写入失败', '文件读取失败', 'copy failed'
    ]
  },
  {
    category: ErrorCategory.DATA,
    tagHints: [
      'datamanager', 'database', 'bookshelf', 'history',
      'noveldatamanager', 'chapterrepository', 'bookrepository'
    ],
    keywords: [
      'sqlite', 'sql', 'db', 'query failed', 'insert failed', 'transaction', 'constraint failed',
      'database locked', 'migration failed', 'deserialize', 'serialize', '数据库', '数据写入失败', '事务回滚'
    ]
  },
  {
    category: ErrorCategory.PARSER,
    tagHints: ['parser', 'extractor', 'htmlparser', 'ebookparser', 'pdf', 'json', 'xml', 'mangaparser', 'comicparser'],
    keywords: [
      'parse', 'parser', 'unexpected token', 'invalid json', 'syntax error', 'xml parse',
      '解析失败', '格式错误', '内容解析异常'
    ]
  },
  {
    category: ErrorCategory.SOURCE,
    tagHints: [
      'source', 'legado', 'suwayomi', 'ruleanalyzer', 'sourcevalidator',
      'sourcemanagementpage', 'booksourcemanagementpage', 'sourcerepositorymanager', 'sourcetester'
    ],
    keywords: [
      '书源', '图源', '源规则', 'source rule', 'rule eval', 'source parse',
      'extension source', 'book source', 'comic source', '规则校验'
    ]
  },
  {
    category: ErrorCategory.WEBVIEW,
    tagHints: ['webview', 'invisiblewebview', 'webviewimage', 'webviewsourcemanager', 'webengine'],
    keywords: ['webview', 'javascript bridge', 'js bridge', 'web runtime', 'evaluatejavascript', '页面脚本']
  },
  {
    category: ErrorCategory.AUTH,
    tagHints: ['login', 'auth', 'credential', 'token', 'cookie', 'anilist', 'oauth'],
    keywords: [
      'unauthorized', 'forbidden', '401', '403', 'login failed', 'auth failed',
      'token expired', 'refresh token', 'invalid token', '登录失败', '认证失败', '鉴权失败'
    ]
  },
  {
    category: ErrorCategory.SYNC,
    tagHints: ['sync', 'webdav', 'backupscheduler', 'widgetdatasync', 'webdavbackupmanager', 'autobackupscheduler'],
    keywords: [
      '同步失败', 'backup failed', 'webdav', 'sync failed', '冲突', '冲突合并',
      'upload failed', 'restore failed', 'auto backup', '增量同步'
    ]
  },
  {
    category: ErrorCategory.UI,
    tagHints: [
      'theme', 'navigation', 'dialog', 'mainmenupage', 'mangareaderpage',
      'mangaviewer', 'imageloadstatemanager', 'splashpage'
    ],
    keywords: ['render', 'layout', 'state update', 'ui', 'build()', '界面', '渲染', '布局', '路由跳转失败']
  },
  {
    category: ErrorCategory.SYSTEM,
    tagHints: ['entryability', 'appinitializationmanager', 'crashrecorderservice', 'errormonitorservice', 'windowmanager'],
    keywords: [
      'lifecycle', 'ability', 'fatal', 'crash', 'oom', 'out of memory',
      'oncreate', 'onforeground', 'onbackground', '初始化失败', '系统', '生命周期'
    ]
  }
];

export class ErrorMonitorService {
  private static instance: ErrorMonitorService;
  private context: common.UIAbilityContext | null = null;
  private logCollector: LogCollector = LogCollector.getInstance();
  private isStarted: boolean = false;
  private errorLogsDir: string = '';
  private logListener: ((entry: LogEntry) => void) | null = null;

  private lastErrorTime: number = 0;
  private lastErrorMessage: string = '';
  private readonly DEBOUNCE_INTERVAL: number = 3000;

  private errorCounter: number = 0;

  private static readonly EXCLUDED_TAGS: string[] = [
    'ErrorMonitorService',
    'CrashRecorderService'
  ];

  private constructor() {}

  public static getInstance(): ErrorMonitorService {
    if (!ErrorMonitorService.instance) {
      ErrorMonitorService.instance = new ErrorMonitorService();
    }
    return ErrorMonitorService.instance;
  }

  public start(context: common.UIAbilityContext): void {
    try {
      this.context = context;
      this.errorLogsDir = `${context.filesDir}/error_logs`;
      this.ensureErrorLogsDir();
      ErrorRecordManager.getInstance().initialize(context);

      if (this.isStarted) {
        console.log(`[NGF] ${TAG}: 已在运行，已刷新上下文与日志目录`);
        return;
      }

      this.logListener = (entry: LogEntry): void => {
        this.onLogEntry(entry);
      };
      this.logCollector.addListener(this.logListener);

      this.isStarted = true;
      console.log(`[NGF] ${TAG}: 错误监控服务已启动`);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: 启动失败: ${msg}`);
    }
  }

  private ensureErrorLogsDir(): void {
    if (!this.errorLogsDir) {
      return;
    }

    try {
      // 若路径存在且是目录，listFileSync 可正常执行
      fs.listFileSync(this.errorLogsDir);
      return;
    } catch {
      // 路径不存在或不是目录，继续修复
    }

    try {
      // 若存在同名文件，先尝试删除
      fs.unlinkSync(this.errorLogsDir);
    } catch {
      // 忽略，可能本来就不存在
    }

    fs.mkdirSync(this.errorLogsDir, true);
  }

  private onLogEntry(entry: LogEntry): void {
    if (entry.level < LogLevel.ERROR) {
      return;
    }

    if (ErrorMonitorService.EXCLUDED_TAGS.indexOf(entry.tag) >= 0) {
      return;
    }

    const isNetwork = this.isNetworkError(entry);

    const now = Date.now();
    if (entry.message === this.lastErrorMessage && (now - this.lastErrorTime) < this.DEBOUNCE_INTERVAL) {
      return;
    }
    this.lastErrorTime = now;
    this.lastErrorMessage = entry.message;

    this.handleProgramError(entry, isNetwork);
  }

  private buildSearchText(entry: LogEntry): string {
    const argsText = entry.args && entry.args.length > 0 ? entry.args.join(' ') : '';
    return `${entry.tag} ${entry.message} ${argsText}`.toLowerCase();
  }

  private isLikelyHttpStatusFailure(text: string): boolean {
    const statusPattern = /status\s*code\s*[:=]?\s*(4\d\d|5\d\d)/i;
    const httpPattern = /\bhttp\s*(4\d\d|5\d\d)\b/i;
    return statusPattern.test(text) || httpPattern.test(text);
  }

  private isNetworkError(entry: LogEntry): boolean {
    const fullText = this.buildSearchText(entry);
    const tagLower = entry.tag.toLowerCase();

    for (let i = 0; i < NETWORK_ERROR_KEYWORDS.length; i++) {
      if (fullText.includes(NETWORK_ERROR_KEYWORDS[i].toLowerCase())) {
        return true;
      }
    }

    for (let i = 0; i < NETWORK_TAG_HINTS.length; i++) {
      if (tagLower.includes(NETWORK_TAG_HINTS[i])) {
        return true;
      }
    }

    if (this.isLikelyHttpStatusFailure(fullText)) {
      return true;
    }

    return false;
  }

  private containsAny(text: string, keywords: string[]): boolean {
    for (let i = 0; i < keywords.length; i++) {
      if (text.includes(keywords[i].toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  private detectErrorCategory(entry: LogEntry, isNetworkError: boolean): ErrorCategory {
    const fullText = this.buildSearchText(entry);
    const tagLower = entry.tag.toLowerCase();

    for (let i = 0; i < CATEGORY_RULES.length; i++) {
      const rule = CATEGORY_RULES[i];
      if (this.containsAny(fullText, rule.keywords)) {
        return rule.category;
      }

      for (let j = 0; j < rule.tagHints.length; j++) {
        if (tagLower.includes(rule.tagHints[j])) {
          return rule.category;
        }
      }
    }

    if (isNetworkError) {
      return ErrorCategory.NETWORK;
    }

    if (entry.level >= LogLevel.FATAL) {
      return ErrorCategory.SYSTEM;
    }

    return ErrorCategory.UNKNOWN;
  }

  private handleProgramError(entry: LogEntry, isNetworkError: boolean): void {
    let recordId = '';
    const category = this.detectErrorCategory(entry, isNetworkError);

    try {
      const levelName = this.getLevelName(entry.level);
      if (isNetworkError) {
        recordId = ErrorRecordManager.getInstance().addNetworkError(entry.tag, entry.message, levelName, '', category);
      } else {
        recordId = ErrorRecordManager.getInstance().addRuntimeError(entry.tag, entry.message, levelName, '', category);
      }
    } catch (regError) {
      const msg = regError instanceof Error ? regError.message : String(regError);
      console.error(`[NGF] ${TAG}: 注册错误记录失败: ${msg}`);
    }

    if (isNetworkError) {
      return;
    }

    try {
      this.notifyErrorDialog(entry);
      this.exportErrorContext(entry, recordId);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: 处理错误时发生异常: ${msg}`);
    }
  }

  private notifyErrorDialog(entry: LogEntry): void {
    try {
      const errorInfo: string = JSON.stringify({
        timestamp: entry.timestamp,
        tag: entry.tag,
        message: entry.message,
        level: entry.level,
        time: this.formatDateTime(entry.timestamp)
      });

      AppStorage.setOrCreate('latestProgramError', errorInfo);
      const currentCount: number = AppStorage.get<number>('programErrorCount') || 0;
      AppStorage.setOrCreate('programErrorCount', currentCount + 1);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: 通知错误弹窗失败: ${msg}`);
    }
  }

  private exportErrorContext(entry: LogEntry, recordId: string = ''): void {
    try {
      const allLogs = this.logCollector.getAllLogs();
      if (allLogs.length === 0) {
        return;
      }

      let errorIndex = -1;
      for (let i = allLogs.length - 1; i >= 0; i--) {
        if (allLogs[i].id === entry.id) {
          errorIndex = i;
          break;
        }
      }

      if (errorIndex < 0) {
        errorIndex = allLogs.length - 1;
      }

      const contextSize = 500;
      const halfContext = Math.floor(contextSize / 2);
      let startIndex = Math.max(0, errorIndex - halfContext);
      let endIndex = Math.min(allLogs.length - 1, errorIndex + halfContext);

      if (errorIndex - startIndex < halfContext) {
        endIndex = Math.min(allLogs.length - 1, endIndex + (halfContext - (errorIndex - startIndex)));
      }
      if (endIndex - errorIndex < halfContext) {
        startIndex = Math.max(0, startIndex - (halfContext - (endIndex - errorIndex)));
      }

      const contextLogs: LogEntry[] = allLogs.slice(startIndex, endIndex + 1);
      const content = this.buildErrorReport(entry, contextLogs, errorIndex - startIndex);
      this.writeErrorLogFile(entry, content, recordId);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NGF] ${TAG}: 导出错误上下文失败: ${msg}`);
    }
  }

  private buildErrorReport(errorEntry: LogEntry, contextLogs: LogEntry[], errorPositionInContext: number): string {
    const sections: string[] = [];

    sections.push('==============================================');
    sections.push('Manxia App Error Report (Auto Export)');
    sections.push('==============================================');
    sections.push('');
    sections.push('Error Summary');
    sections.push(`  Time: ${this.formatDateTime(errorEntry.timestamp)}`);
    sections.push(`  Tag: ${errorEntry.tag}`);
    sections.push(`  Level: ${this.getLevelName(errorEntry.level)}`);
    sections.push(`  Message: ${errorEntry.message}`);
    if (errorEntry.args && errorEntry.args.length > 0) {
      sections.push(`  Args: ${errorEntry.args.join(' ')}`);
    }
    sections.push('');

    sections.push('Device Info');
    try {
      sections.push(`  Model: ${deviceInfo.productModel || 'Unknown'} (${deviceInfo.brand || 'Unknown'})`);
      sections.push(`  OS: ${deviceInfo.osFullName || 'Unknown'}`);
    } catch {
      sections.push('  Device info unavailable');
    }
    sections.push('');

    sections.push('----------------------------------------------');
    sections.push(`Context Logs (total ${contextLogs.length}, error at #${errorPositionInContext + 1})`);
    sections.push('----------------------------------------------');
    sections.push('');

    for (let i = 0; i < contextLogs.length; i++) {
      const log = contextLogs[i];
      const time = this.formatDateTime(log.timestamp);
      const levelName = this.getLevelName(log.level);
      const marker = (i === errorPositionInContext) ? '***' : '   ';
      let line = `${marker}[${time}] [${levelName}] [${log.tag}] ${log.message}`;
      if (log.args && log.args.length > 0) {
        line += ` ${log.args.join(' ')}`;
      }
      if (log.details) {
        line += `\n      details: ${log.details}`;
      }
      sections.push(line);
    }

    return sections.join('\n');
  }

  private writeTextFile(filePath: string, content: string): void {
    const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, content);
    } finally {
      try {
        fs.closeSync(file);
      } catch {
        // ignore close failure
      }
    }
  }

  private writeFileWithRetry(filePath: string, content: string): void {
    let lastError = '';

    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        if (attempt > 1) {
          this.ensureErrorLogsDir();
        }
        this.writeTextFile(filePath, content);
        return;
      } catch (error) {
        lastError = error instanceof Error ? error.message : String(error);
        if (attempt === 2) {
          throw error as Error;
        }
      }
    }

    throw new Error(lastError || 'unknown write failure');
  }

  private writeErrorLogFile(entry: LogEntry, content: string, recordId: string = ''): void {
    this.errorCounter++;
    const dateStr = this.formatDateTime(entry.timestamp);
    const safeDate = dateStr.replace(/[:/]/g, '-').replace(/\s/g, '_').replace(/\./g, '-');
    const fileName = `error_${safeDate}_${this.errorCounter}.txt`;
    const sandboxPath = `${this.errorLogsDir}/${fileName}`;

    try {
      this.ensureErrorLogsDir();
      this.writeFileWithRetry(sandboxPath, content);
      console.log(`[NGF] ${TAG}: 错误日志已保存到沙箱: ${fileName}`);

      this.tryCopyToDownload(sandboxPath, fileName);

      if (recordId) {
        try {
          ErrorRecordManager.getInstance().updateRecordLogFileName(recordId, fileName);
        } catch {
          // 不影响主流程
        }
      }

      this.cleanOldErrorLogs();
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      const filesDir = this.context ? this.context.filesDir : 'null';
      console.error(`[NGF] ${TAG}: 写入错误日志失败: ${msg}; path=${sandboxPath}; dir=${this.errorLogsDir}; filesDir=${filesDir}; started=${this.isStarted}`);
    }
  }

  private tryCopyToDownload(sourcePath: string, fileName: string): void {
    try {
      const downloadDirManager = DownloadDirManager.getInstance();
      if (!downloadDirManager.isReady()) {
        return;
      }
      const logsDir = downloadDirManager.ensureDirectory('logs');
      const targetPath = `${logsDir}/${fileName}`;
      fs.copyFileSync(sourcePath, targetPath);
      console.log(`[NGF] ${TAG}: 错误日志已复制到 Download 目录`);
    } catch {
      // 复制失败不影响主流程
    }
  }

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
          // ignore
        }
      }
    } catch {
      // cleanup failure should not break main flow
    }
  }

  public stop(): void {
    if (this.logListener) {
      this.logCollector.removeListener(this.logListener);
      this.logListener = null;
    }
    this.isStarted = false;
    console.log(`[NGF] ${TAG}: 错误监控服务已停止`);
  }

  public isRunning(): boolean {
    return this.isStarted;
  }

  public getErrorLogsDir(): string {
    return this.errorLogsDir;
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

export function getErrorMonitorService(): ErrorMonitorService {
  return ErrorMonitorService.getInstance();
}
