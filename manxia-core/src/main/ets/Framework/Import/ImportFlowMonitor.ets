import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  ImportFlowContentType,
  ImportFlowEntrySource,
  ImportFlowEvent,
  ImportFlowEventType,
  ImportFlowSessionInfo,
  ImportFlowSeverity,
  ImportFlowSnapshot,
  ImportFlowSummary
} from 'manxia_core/src/main/ets/Framework/Import/ImportFlowTypes';

const TAG = 'ImportFlowMonitor';

export class ImportFlowMonitor {
  private static instance: ImportFlowMonitor | null = null;
  private static readonly MAX_RECENT_SESSIONS: number = 24;
  private static readonly MAX_RECENT_EVENTS: number = 260;
  private static readonly MAX_FAILED_EVENTS: number = 80;
  private static readonly MAX_SLOW_EVENTS: number = 80;
  private static readonly DOWNLOAD_SCAN_SLOW_MS: number = 1000;
  private static readonly FILE_CLASSIFY_SLOW_MS: number = 300;
  private static readonly ARCHIVE_PARSE_SLOW_MS: number = 3000;
  private static readonly COPY_SLOW_MS: number = 5000;
  private static readonly TXT_PARSE_SLOW_MS: number = 2000;
  private static readonly PDF_CONVERT_SLOW_MS: number = 8000;
  private static readonly DUPLICATE_DETECT_SLOW_MS: number = 1000;
  private static readonly DB_WRITE_SLOW_MS: number = 1500;
  private static readonly SINGLE_SESSION_SLOW_MS: number = 15000;
  private static readonly BATCH_SESSION_SLOW_MS: number = 30000;

  private activeSessions: Map<string, ImportFlowSummary> = new Map<string, ImportFlowSummary>();
  private recentSessions: ImportFlowSummary[] = new Array<ImportFlowSummary>();
  private recentEvents: ImportFlowEvent[] = new Array<ImportFlowEvent>();
  private failedEvents: ImportFlowEvent[] = new Array<ImportFlowEvent>();
  private slowEvents: ImportFlowEvent[] = new Array<ImportFlowEvent>();
  private sequence: number = 0;

  private constructor() {}

  public static getInstance(): ImportFlowMonitor {
    if (ImportFlowMonitor.instance === null) {
      ImportFlowMonitor.instance = new ImportFlowMonitor();
    }
    return ImportFlowMonitor.instance;
  }

  public createSessionId(prefix: string): string {
    this.sequence = this.sequence + 1;
    const normalizedPrefix: string = prefix.length > 0 ? prefix : 'import_flow';
    return `${normalizedPrefix}_${Date.now()}_${this.sequence}`;
  }

  public ensureSession(info: ImportFlowSessionInfo): string {
    try {
      if (!info.sessionId || info.sessionId.length <= 0) {
        info.sessionId = this.createSessionId('import_flow');
      }
      if (info.startedAt <= 0) {
        info.startedAt = Date.now();
      }

      const existing: ImportFlowSummary | undefined = this.activeSessions.get(info.sessionId);
      if (existing) {
        this.mergeSessionInfo(existing, info);
        return info.sessionId;
      }

      const summary: ImportFlowSummary = new ImportFlowSummary();
      summary.sessionId = info.sessionId;
      summary.entrySource = info.entrySource;
      summary.contentType = info.contentType;
      summary.sourceUri = info.sourceUri;
      summary.targetPath = info.targetPath;
      summary.displayName = info.displayName;
      summary.fileCount = info.fileCount;
      summary.batchMode = info.batchMode;
      summary.transferRecordId = info.transferRecordId;
      summary.pageName = info.pageName;
      summary.startedAt = info.startedAt;
      this.activeSessions.set(info.sessionId, summary);
      this.pushRecentSession(summary);

      const event: ImportFlowEvent = this.createEvent(info.sessionId, ImportFlowEventType.SESSION_START, 'ensure_session');
      event.entrySource = info.entrySource;
      event.contentType = info.contentType;
      event.sourceUri = info.sourceUri;
      event.targetPath = info.targetPath;
      event.displayName = info.displayName;
      event.fileCount = info.fileCount;
      event.batchMode = info.batchMode;
      event.transferRecordId = info.transferRecordId;
      event.detail = `page=${info.pageName}, files=${info.fileCount}, batch=${info.batchMode}`;
      this.record(event);
      return info.sessionId;
    } catch (error) {
      logger.warn(TAG, `创建导入链路会话失败: ${String(error)}`);
      return info.sessionId;
    }
  }

  public record(event: ImportFlowEvent): void {
    try {
      if (!event.sessionId || event.sessionId.length <= 0) {
        event.sessionId = 'unbound';
      }
      if (event.timestamp <= 0) {
        event.timestamp = Date.now();
      }
      const summary: ImportFlowSummary | undefined = this.activeSessions.get(event.sessionId);
      if (summary) {
        this.applyEventToSummary(summary, event);
      }
      if (this.isSlowEvent(event, summary)) {
        this.pushSlowEvent(event);
        logger.warn(TAG, `导入慢事件: ${this.describeEvent(event)}, elapsed=${event.elapsedMs}ms`);
      }
      if (this.isFailureEvent(event)) {
        this.pushFailedEvent(event);
        logger.error(TAG, `导入失败事件: ${this.describeEvent(event)}, error=${event.errorMessage}`);
      }
      this.pushRecentEvent(event);
      this.logEvent(event);
    } catch (error) {
      logger.warn(TAG, `记录导入链路失败: ${String(error)}`);
    }
  }

  public endSession(sessionId: string, reason: string): void {
    if (!sessionId || sessionId.length <= 0) {
      return;
    }
    const summary: ImportFlowSummary | undefined = this.activeSessions.get(sessionId);
    const event: ImportFlowEvent = this.createEvent(sessionId, ImportFlowEventType.SESSION_END, reason);
    if (summary) {
      event.entrySource = summary.entrySource;
      event.contentType = summary.contentType;
      event.sourceUri = summary.sourceUri;
      event.targetPath = summary.targetPath;
      event.displayName = summary.displayName;
      event.fileCount = summary.fileCount;
      event.batchMode = summary.batchMode;
      event.transferRecordId = summary.transferRecordId;
      event.currentIndex = summary.completedItems;
      event.totalCount = summary.totalItems;
      event.elapsedMs = summary.startedAt > 0 ? Date.now() - summary.startedAt : 0;
    }
    this.record(event);
    if (summary) {
      summary.endedAt = Date.now();
      summary.endReason = reason;
      this.activeSessions.delete(sessionId);
    }
  }

  public createSnapshot(): ImportFlowSnapshot {
    const snapshot: ImportFlowSnapshot = new ImportFlowSnapshot();
    snapshot.activeSessionCount = this.activeSessions.size;
    snapshot.recentSessionCount = this.recentSessions.length;
    snapshot.recentEventCount = this.recentEvents.length;
    snapshot.failedEventCount = this.failedEvents.length;
    snapshot.slowEventCount = this.slowEvents.length;
    snapshot.recentSessions = this.recentSessions.slice();
    snapshot.recentEvents = this.recentEvents.slice();
    snapshot.failedEvents = this.failedEvents.slice();
    snapshot.slowEvents = this.slowEvents.slice();
    return snapshot;
  }

  public createEvent(sessionId: string, eventType: ImportFlowEventType, reason: string): ImportFlowEvent {
    const event: ImportFlowEvent = new ImportFlowEvent();
    event.sessionId = sessionId;
    event.eventType = eventType;
    event.reason = reason;
    event.timestamp = Date.now();
    return event;
  }

  public buildSessionInfo(
    sessionId: string,
    entrySource: ImportFlowEntrySource,
    contentType: ImportFlowContentType,
    pageName: string
  ): ImportFlowSessionInfo {
    const info: ImportFlowSessionInfo = new ImportFlowSessionInfo();
    info.sessionId = sessionId;
    info.entrySource = entrySource;
    info.contentType = contentType;
    info.pageName = pageName;
    info.startedAt = Date.now();
    return info;
  }

  private mergeSessionInfo(summary: ImportFlowSummary, info: ImportFlowSessionInfo): void {
    if (info.entrySource !== ImportFlowEntrySource.UNKNOWN) {
      summary.entrySource = info.entrySource;
    }
    if (info.contentType !== ImportFlowContentType.UNKNOWN) {
      summary.contentType = info.contentType;
    }
    if (info.sourceUri.length > 0) {
      summary.sourceUri = info.sourceUri;
    }
    if (info.targetPath.length > 0) {
      summary.targetPath = info.targetPath;
    }
    if (info.displayName.length > 0) {
      summary.displayName = info.displayName;
    }
    if (info.fileCount > 0) {
      summary.fileCount = info.fileCount;
    }
    summary.batchMode = info.batchMode;
    if (info.transferRecordId.length > 0) {
      summary.transferRecordId = info.transferRecordId;
    }
    if (info.pageName.length > 0) {
      summary.pageName = info.pageName;
    }
  }

  private applyEventToSummary(summary: ImportFlowSummary, event: ImportFlowEvent): void {
    summary.totalEvents = summary.totalEvents + 1;
    summary.lastEventType = event.eventType;
    if (event.entrySource !== ImportFlowEntrySource.UNKNOWN) {
      summary.entrySource = event.entrySource;
    }
    if (event.contentType !== ImportFlowContentType.UNKNOWN) {
      summary.contentType = event.contentType;
    }
    if (event.sourceUri.length > 0) {
      summary.sourceUri = event.sourceUri;
    }
    if (event.targetPath.length > 0) {
      summary.targetPath = event.targetPath;
    }
    if (event.displayName.length > 0) {
      summary.displayName = event.displayName;
    }
    if (event.fileCount > 0) {
      summary.fileCount = event.fileCount;
    }
    if (event.transferRecordId.length > 0) {
      summary.transferRecordId = event.transferRecordId;
    }
    if (event.totalCount > 0) {
      summary.totalItems = event.totalCount;
    }
    if (event.currentIndex > 0) {
      summary.completedItems = event.currentIndex;
    }
    if (this.isFailureEvent(event)) {
      summary.failedEvents = summary.failedEvents + 1;
    }
    if (this.isSlowEvent(event, summary)) {
      summary.slowEvents = summary.slowEvents + 1;
    }
    if (event.cacheHit) {
      summary.cacheHits = summary.cacheHits + 1;
    } else if (event.eventType === ImportFlowEventType.ARCHIVE_PARSE_STARTED ||
      event.eventType === ImportFlowEventType.DUPLICATE_DETECT_STARTED) {
      summary.cacheMisses = summary.cacheMisses + 1;
    }
    if (event.eventType === ImportFlowEventType.ARCHIVE_PARSE_COMPLETED) {
      summary.parsedFiles = summary.parsedFiles + 1;
    }
    if (event.eventType === ImportFlowEventType.COPY_COMPLETED) {
      summary.copiedFiles = summary.copiedFiles + 1;
    }
    if (event.eventType === ImportFlowEventType.DB_WRITE_COMPLETED) {
      summary.dbWrites = summary.dbWrites + 1;
    }
  }

  private isSlowEvent(event: ImportFlowEvent, summary: ImportFlowSummary | undefined): boolean {
    if (event.elapsedMs <= 0) {
      return false;
    }
    if (event.eventType === ImportFlowEventType.DOWNLOAD_SCAN_COMPLETED) {
      return event.elapsedMs >= ImportFlowMonitor.DOWNLOAD_SCAN_SLOW_MS;
    }
    if (event.eventType === ImportFlowEventType.FILE_CLASSIFIED) {
      return event.elapsedMs >= ImportFlowMonitor.FILE_CLASSIFY_SLOW_MS;
    }
    if (event.eventType === ImportFlowEventType.ARCHIVE_PARSE_COMPLETED ||
      event.eventType === ImportFlowEventType.ARCHIVE_PARSE_FAILED) {
      return event.elapsedMs >= ImportFlowMonitor.ARCHIVE_PARSE_SLOW_MS;
    }
    if (event.eventType === ImportFlowEventType.COPY_COMPLETED) {
      return event.elapsedMs >= ImportFlowMonitor.COPY_SLOW_MS;
    }
    if (event.eventType === ImportFlowEventType.TXT_RULE_PARSE_COMPLETED ||
      event.eventType === ImportFlowEventType.TXT_RULE_PARSE_FAILED) {
      return event.elapsedMs >= ImportFlowMonitor.TXT_PARSE_SLOW_MS;
    }
    if (event.eventType === ImportFlowEventType.PDF_CONVERT_COMPLETED ||
      event.eventType === ImportFlowEventType.PDF_TASK_COMPLETED ||
      event.eventType === ImportFlowEventType.PDF_TASK_FAILED) {
      return event.elapsedMs >= ImportFlowMonitor.PDF_CONVERT_SLOW_MS;
    }
    if (event.eventType === ImportFlowEventType.DUPLICATE_DETECT_COMPLETED) {
      return event.elapsedMs >= ImportFlowMonitor.DUPLICATE_DETECT_SLOW_MS;
    }
    if (event.eventType === ImportFlowEventType.DB_WRITE_COMPLETED) {
      return event.elapsedMs >= ImportFlowMonitor.DB_WRITE_SLOW_MS;
    }
    if (event.eventType === ImportFlowEventType.SESSION_END) {
      const batchMode: boolean = summary ? summary.batchMode : event.batchMode;
      return event.elapsedMs >= (batchMode ? ImportFlowMonitor.BATCH_SESSION_SLOW_MS : ImportFlowMonitor.SINGLE_SESSION_SLOW_MS);
    }
    return false;
  }

  private isFailureEvent(event: ImportFlowEvent): boolean {
    return !event.success ||
      event.severity === ImportFlowSeverity.ERROR ||
      event.eventType === ImportFlowEventType.ERROR ||
      event.eventType === ImportFlowEventType.ARCHIVE_PARSE_FAILED ||
      event.eventType === ImportFlowEventType.TXT_RULE_PARSE_FAILED ||
      event.eventType === ImportFlowEventType.PDF_TASK_FAILED;
  }

  private logEvent(event: ImportFlowEvent): void {
    const text: string = this.describeEvent(event);
    if (event.eventType === ImportFlowEventType.SESSION_START ||
      event.eventType === ImportFlowEventType.SESSION_END) {
      logger.lifecycle(TAG, event.eventType, text);
      return;
    }
    if (event.severity === ImportFlowSeverity.DEBUG) {
      logger.debug(TAG, text);
    } else if (event.severity === ImportFlowSeverity.WARN) {
      logger.warn(TAG, text);
    } else if (event.severity === ImportFlowSeverity.ERROR) {
      logger.error(TAG, text);
    } else {
      logger.info(TAG, text);
    }
    if (event.metricName.length > 0) {
      logger.performance(TAG, event.metricName, event.metricValue, event.metricUnit);
    }
  }

  private describeEvent(event: ImportFlowEvent): string {
    return `flow=${event.eventType}, session=${event.sessionId}, source=${event.entrySource}, type=${event.contentType}, display="${event.displayName}", file="${event.fileName}", progress=${event.currentIndex}/${event.totalCount}, cacheHit=${event.cacheHit}, task=${event.taskId}, reason=${event.reason}, success=${event.success}, detail=${event.detail}`;
  }

  private pushRecentSession(summary: ImportFlowSummary): void {
    this.recentSessions.push(summary);
    while (this.recentSessions.length > ImportFlowMonitor.MAX_RECENT_SESSIONS) {
      this.recentSessions.shift();
    }
  }

  private pushRecentEvent(event: ImportFlowEvent): void {
    this.recentEvents.push(event);
    while (this.recentEvents.length > ImportFlowMonitor.MAX_RECENT_EVENTS) {
      this.recentEvents.shift();
    }
  }

  private pushFailedEvent(event: ImportFlowEvent): void {
    this.failedEvents.push(event);
    while (this.failedEvents.length > ImportFlowMonitor.MAX_FAILED_EVENTS) {
      this.failedEvents.shift();
    }
  }

  private pushSlowEvent(event: ImportFlowEvent): void {
    this.slowEvents.push(event);
    while (this.slowEvents.length > ImportFlowMonitor.MAX_SLOW_EVENTS) {
      this.slowEvents.shift();
    }
  }
}

export function getImportFlowMonitor(): ImportFlowMonitor {
  return ImportFlowMonitor.getInstance();
}
