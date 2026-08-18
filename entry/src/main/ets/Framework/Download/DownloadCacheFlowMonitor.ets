import { logger } from '../../Utils/Logger';
import {
  DownloadCacheContentType,
  DownloadCacheEntrySource,
  DownloadCacheFlowEvent,
  DownloadCacheFlowEventType,
  DownloadCacheFlowSessionInfo,
  DownloadCacheFlowSeverity,
  DownloadCacheFlowSnapshot,
  DownloadCacheFlowStage,
  DownloadCacheFlowSummary
} from './DownloadCacheFlowTypes';
import {
  getNetworkTransportFailureCoordinator,
  NetworkTransportFailureCoordinator
} from '../Network/NetworkTransportFailureCoordinator';

const TAG = 'DownloadCacheFlowMonitor';

export class DownloadCacheFlowMonitor {
  private static instance: DownloadCacheFlowMonitor | null = null;
  private static readonly MAX_RECENT_SESSIONS: number = 32;
  private static readonly MAX_RECENT_EVENTS: number = 320;
  private static readonly MAX_FAILED_EVENTS: number = 100;
  private static readonly MAX_SLOW_EVENTS: number = 100;
  private static readonly TASK_CREATE_SLOW_MS: number = 500;
  private static readonly PAGE_LIST_SLOW_MS: number = 3000;
  private static readonly NETWORK_SLOW_MS: number = 5000;
  private static readonly WEBVIEW_FALLBACK_SLOW_MS: number = 10000;
  private static readonly IMAGE_PROCESS_SLOW_MS: number = 1500;
  private static readonly DISK_WRITE_SLOW_MS: number = 1000;
  private static readonly DB_FLUSH_SLOW_MS: number = 800;
  private static readonly ARCHIVE_SLOW_MS: number = 8000;
  private static readonly CACHE_STATUS_SLOW_MS: number = 1500;
  private static readonly CHAPTER_DOWNLOAD_SLOW_MS: number = 30000;

  private activeSessions: Map<string, DownloadCacheFlowSummary> = new Map<string, DownloadCacheFlowSummary>();
  private recentSessions: DownloadCacheFlowSummary[] = new Array<DownloadCacheFlowSummary>();
  private recentEvents: DownloadCacheFlowEvent[] = new Array<DownloadCacheFlowEvent>();
  private failedEvents: DownloadCacheFlowEvent[] = new Array<DownloadCacheFlowEvent>();
  private slowEvents: DownloadCacheFlowEvent[] = new Array<DownloadCacheFlowEvent>();
  private sequence: number = 0;
  private transportFailureCoordinator: NetworkTransportFailureCoordinator =
    getNetworkTransportFailureCoordinator();

  private constructor() {}

  public static getInstance(): DownloadCacheFlowMonitor {
    if (DownloadCacheFlowMonitor.instance === null) {
      DownloadCacheFlowMonitor.instance = new DownloadCacheFlowMonitor();
    }
    return DownloadCacheFlowMonitor.instance;
  }

  public createSessionId(prefix: string): string {
    this.sequence = this.sequence + 1;
    const normalizedPrefix: string = prefix.length > 0 ? prefix : 'download_cache_flow';
    return `${normalizedPrefix}_${Date.now()}_${this.sequence}`;
  }

  public ensureSession(info: DownloadCacheFlowSessionInfo): string {
    try {
      if (info.sessionId.length <= 0) {
        info.sessionId = this.createSessionId('download_cache_flow');
      }
      if (info.startedAt <= 0) {
        info.startedAt = Date.now();
      }

      const existing: DownloadCacheFlowSummary | undefined = this.activeSessions.get(info.sessionId);
      if (existing) {
        this.mergeSessionInfo(existing, info);
        return info.sessionId;
      }

      const summary: DownloadCacheFlowSummary = new DownloadCacheFlowSummary();
      summary.sessionId = info.sessionId;
      summary.entrySource = info.entrySource;
      summary.contentType = info.contentType;
      summary.contentId = info.contentId;
      summary.contentTitle = info.contentTitle;
      summary.chapterId = info.chapterId;
      summary.chapterTitle = info.chapterTitle;
      summary.taskId = info.taskId;
      summary.sourceId = info.sourceId;
      summary.sourceKey = info.sourceKey;
      summary.startedAt = info.startedAt;
      summary.totalItems = info.totalCount;
      this.activeSessions.set(info.sessionId, summary);
      this.pushRecentSession(summary);

      const event: DownloadCacheFlowEvent = this.createEvent(info.sessionId, DownloadCacheFlowEventType.SESSION_START, DownloadCacheFlowStage.SESSION, 'ensure_session');
      event.entrySource = info.entrySource;
      event.contentType = info.contentType;
      event.contentId = info.contentId;
      event.contentTitle = info.contentTitle;
      event.chapterId = info.chapterId;
      event.chapterTitle = info.chapterTitle;
      event.taskId = info.taskId;
      event.sourceId = info.sourceId;
      event.sourceKey = info.sourceKey;
      event.url = info.url;
      event.cacheKey = info.cacheKey;
      event.totalCount = info.totalCount;
      event.detail = `page=${info.pageName}, batch=${info.batchMode}`;
      this.record(event);
      return info.sessionId;
    } catch (error) {
      logger.warn(TAG, `创建下载缓存链路会话失败: ${String(error)}`);
      return info.sessionId;
    }
  }

  public record(event: DownloadCacheFlowEvent): void {
    try {
      if (event.sessionId.length <= 0) {
        event.sessionId = 'unbound';
      }
      if (event.timestamp <= 0) {
        event.timestamp = Date.now();
      }

      const summary: DownloadCacheFlowSummary | undefined = this.activeSessions.get(event.sessionId);
      if (summary) {
        this.applyEventToSummary(summary, event);
      }

      if (this.isSlowEvent(event, summary)) {
        this.pushSlowEvent(event);
        logger.warn(TAG, `下载缓存慢事件: ${this.describeEvent(event)}, elapsed=${event.elapsedMs}ms`);
      }
      if (this.isFailureEvent(event)) {
        this.pushFailedEvent(event);
      }
      this.pushRecentEvent(event);
      this.logEvent(event);
    } catch (error) {
      logger.warn(TAG, `记录下载缓存链路失败: ${String(error)}`);
    }
  }

  public endSession(sessionId: string, reason: string): void {
    if (sessionId.length <= 0) {
      return;
    }
    const summary: DownloadCacheFlowSummary | undefined = this.activeSessions.get(sessionId);
    const event: DownloadCacheFlowEvent = this.createEvent(sessionId, DownloadCacheFlowEventType.SESSION_END, DownloadCacheFlowStage.SESSION, reason);
    if (summary) {
      event.entrySource = summary.entrySource;
      event.contentType = summary.contentType;
      event.contentId = summary.contentId;
      event.contentTitle = summary.contentTitle;
      event.chapterId = summary.chapterId;
      event.chapterTitle = summary.chapterTitle;
      event.taskId = summary.taskId;
      event.sourceId = summary.sourceId;
      event.sourceKey = summary.sourceKey;
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

  public createSnapshot(): DownloadCacheFlowSnapshot {
    const snapshot: DownloadCacheFlowSnapshot = new DownloadCacheFlowSnapshot();
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

  public createEvent(
    sessionId: string,
    eventType: DownloadCacheFlowEventType,
    stage: DownloadCacheFlowStage,
    reason: string
  ): DownloadCacheFlowEvent {
    const event: DownloadCacheFlowEvent = new DownloadCacheFlowEvent();
    event.sessionId = sessionId;
    event.eventType = eventType;
    event.stage = stage;
    event.reason = reason;
    event.timestamp = Date.now();
    return event;
  }

  public buildSessionInfo(
    sessionId: string,
    entrySource: DownloadCacheEntrySource,
    contentType: DownloadCacheContentType,
    contentId: string
  ): DownloadCacheFlowSessionInfo {
    const info: DownloadCacheFlowSessionInfo = new DownloadCacheFlowSessionInfo();
    info.sessionId = sessionId;
    info.entrySource = entrySource;
    info.contentType = contentType;
    info.contentId = contentId;
    info.startedAt = Date.now();
    return info;
  }

  private mergeSessionInfo(summary: DownloadCacheFlowSummary, info: DownloadCacheFlowSessionInfo): void {
    if (info.entrySource !== DownloadCacheEntrySource.UNKNOWN) {
      summary.entrySource = info.entrySource;
    }
    if (info.contentType !== DownloadCacheContentType.UNKNOWN) {
      summary.contentType = info.contentType;
    }
    if (info.contentId.length > 0) {
      summary.contentId = info.contentId;
    }
    if (info.contentTitle.length > 0) {
      summary.contentTitle = info.contentTitle;
    }
    if (info.chapterId.length > 0) {
      summary.chapterId = info.chapterId;
    }
    if (info.chapterTitle.length > 0) {
      summary.chapterTitle = info.chapterTitle;
    }
    if (info.taskId.length > 0) {
      summary.taskId = info.taskId;
    }
    if (info.sourceId > 0) {
      summary.sourceId = info.sourceId;
    }
    if (info.sourceKey.length > 0) {
      summary.sourceKey = info.sourceKey;
    }
    if (info.totalCount > 0) {
      summary.totalItems = info.totalCount;
    }
  }

  private applyEventToSummary(summary: DownloadCacheFlowSummary, event: DownloadCacheFlowEvent): void {
    summary.totalEvents = summary.totalEvents + 1;
    summary.lastEventType = event.eventType;
    if (event.entrySource !== DownloadCacheEntrySource.UNKNOWN) {
      summary.entrySource = event.entrySource;
    }
    if (event.contentType !== DownloadCacheContentType.UNKNOWN) {
      summary.contentType = event.contentType;
    }
    if (event.contentId.length > 0) {
      summary.contentId = event.contentId;
    }
    if (event.contentTitle.length > 0) {
      summary.contentTitle = event.contentTitle;
    }
    if (event.chapterId.length > 0) {
      summary.chapterId = event.chapterId;
    }
    if (event.chapterTitle.length > 0) {
      summary.chapterTitle = event.chapterTitle;
    }
    if (event.taskId.length > 0) {
      summary.taskId = event.taskId;
    }
    if (event.sourceId > 0) {
      summary.sourceId = event.sourceId;
    }
    if (event.sourceKey.length > 0) {
      summary.sourceKey = event.sourceKey;
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
    }
    if (event.eventType === DownloadCacheFlowEventType.HTTP_STARTED) {
      summary.networkRequests = summary.networkRequests + 1;
    }
    if (event.eventType === DownloadCacheFlowEventType.DB_FLUSH_COMPLETED) {
      summary.dbFlushes = summary.dbFlushes + 1;
    }
    if (event.eventType === DownloadCacheFlowEventType.ARCHIVE_COMPLETED) {
      summary.archives = summary.archives + 1;
    }
  }

  private isSlowEvent(event: DownloadCacheFlowEvent, summary: DownloadCacheFlowSummary | undefined): boolean {
    if (event.elapsedMs <= 0) {
      return false;
    }
    if (event.eventType === DownloadCacheFlowEventType.TASK_CREATED) {
      return event.elapsedMs >= DownloadCacheFlowMonitor.TASK_CREATE_SLOW_MS;
    }
    if (event.eventType === DownloadCacheFlowEventType.PAGE_LIST_FETCH_COMPLETED ||
      event.eventType === DownloadCacheFlowEventType.PAGE_LIST_FETCH_FAILED) {
      return event.elapsedMs >= DownloadCacheFlowMonitor.PAGE_LIST_SLOW_MS;
    }
    if (event.eventType === DownloadCacheFlowEventType.HTTP_COMPLETED ||
      event.eventType === DownloadCacheFlowEventType.HTTP_FAILED ||
      event.eventType === DownloadCacheFlowEventType.IMAGE_DOWNLOAD_COMPLETED ||
      event.eventType === DownloadCacheFlowEventType.IMAGE_DOWNLOAD_FAILED) {
      return event.elapsedMs >= DownloadCacheFlowMonitor.NETWORK_SLOW_MS;
    }
    if (event.eventType === DownloadCacheFlowEventType.WEBVIEW_FALLBACK_COMPLETED ||
      event.eventType === DownloadCacheFlowEventType.WEBVIEW_FALLBACK_FAILED) {
      return event.elapsedMs >= DownloadCacheFlowMonitor.WEBVIEW_FALLBACK_SLOW_MS;
    }
    if (event.eventType === DownloadCacheFlowEventType.IMAGE_PROCESS_COMPLETED ||
      event.eventType === DownloadCacheFlowEventType.IMAGE_PROCESS_FAILED) {
      return event.elapsedMs >= DownloadCacheFlowMonitor.IMAGE_PROCESS_SLOW_MS;
    }
    if (event.eventType === DownloadCacheFlowEventType.DISK_WRITE_COMPLETED ||
      event.eventType === DownloadCacheFlowEventType.DISK_WRITE_FAILED) {
      return event.elapsedMs >= DownloadCacheFlowMonitor.DISK_WRITE_SLOW_MS;
    }
    if (event.eventType === DownloadCacheFlowEventType.DB_FLUSH_COMPLETED ||
      event.eventType === DownloadCacheFlowEventType.DB_FLUSH_FAILED) {
      return event.elapsedMs >= DownloadCacheFlowMonitor.DB_FLUSH_SLOW_MS;
    }
    if (event.eventType === DownloadCacheFlowEventType.ARCHIVE_COMPLETED ||
      event.eventType === DownloadCacheFlowEventType.ARCHIVE_FAILED) {
      return event.elapsedMs >= DownloadCacheFlowMonitor.ARCHIVE_SLOW_MS;
    }
    if (event.eventType === DownloadCacheFlowEventType.CACHE_STATUS_COMPLETED ||
      event.eventType === DownloadCacheFlowEventType.CACHE_STATUS_FAILED) {
      return event.elapsedMs >= DownloadCacheFlowMonitor.CACHE_STATUS_SLOW_MS;
    }
    if (event.eventType === DownloadCacheFlowEventType.SESSION_END) {
      const totalItems: number = summary ? summary.totalItems : event.totalCount;
      return totalItems > 1 && event.elapsedMs >= DownloadCacheFlowMonitor.CHAPTER_DOWNLOAD_SLOW_MS;
    }
    return false;
  }

  private isFailureEvent(event: DownloadCacheFlowEvent): boolean {
    return !event.success ||
      event.severity === DownloadCacheFlowSeverity.ERROR ||
      event.eventType === DownloadCacheFlowEventType.ERROR ||
      event.eventType === DownloadCacheFlowEventType.PAGE_LIST_FETCH_FAILED ||
      event.eventType === DownloadCacheFlowEventType.IMAGE_DOWNLOAD_FAILED ||
      event.eventType === DownloadCacheFlowEventType.HTTP_FAILED ||
      event.eventType === DownloadCacheFlowEventType.WEBVIEW_FALLBACK_FAILED ||
      event.eventType === DownloadCacheFlowEventType.IMAGE_PROCESS_FAILED ||
      event.eventType === DownloadCacheFlowEventType.DISK_WRITE_FAILED ||
      event.eventType === DownloadCacheFlowEventType.DB_FLUSH_FAILED ||
      event.eventType === DownloadCacheFlowEventType.ARCHIVE_FAILED ||
      event.eventType === DownloadCacheFlowEventType.CACHE_STATUS_FAILED;
  }

  private logEvent(event: DownloadCacheFlowEvent): void {
    const text: string = this.describeEvent(event);
    if (event.eventType === DownloadCacheFlowEventType.SESSION_START ||
      event.eventType === DownloadCacheFlowEventType.SESSION_END) {
      logger.lifecycle(TAG, event.eventType, text);
      return;
    }
    if (event.severity === DownloadCacheFlowSeverity.DEBUG) {
      logger.debug(TAG, text);
    } else if (event.severity === DownloadCacheFlowSeverity.WARN) {
      logger.warn(TAG, text);
    } else if (event.severity === DownloadCacheFlowSeverity.ERROR) {
      const errorText: string = event.errorMessage.length > 0 ? `${text}, error=${event.errorMessage}` : text;
      if (this.transportFailureCoordinator.isRecognizedFailureMessage(event.errorMessage)) {
        logger.warn(TAG, `下载缓存传输失败（已聚合）: ${errorText}`);
      } else {
        logger.error(TAG, errorText);
      }
    } else {
      logger.info(TAG, text);
    }
    if (event.metricName.length > 0) {
      logger.performance(TAG, event.metricName, event.metricValue, event.metricUnit);
    }
  }

  private describeEvent(event: DownloadCacheFlowEvent): string {
    return `flow=${event.eventType}, stage=${event.stage}, session=${event.sessionId}, task=${event.taskId}, content=${event.contentId}, chapter=${event.chapterId}, source=${event.sourceId}/${event.sourceKey}, progress=${event.downloadedCount}/${event.totalCount}, cacheHit=${event.cacheHit}, visible=${event.visibleLoad}, reason=${event.reason}, success=${event.success}, detail=${event.detail}`;
  }

  private pushRecentSession(summary: DownloadCacheFlowSummary): void {
    this.recentSessions.push(summary);
    while (this.recentSessions.length > DownloadCacheFlowMonitor.MAX_RECENT_SESSIONS) {
      this.recentSessions.shift();
    }
  }

  private pushRecentEvent(event: DownloadCacheFlowEvent): void {
    this.recentEvents.push(event);
    while (this.recentEvents.length > DownloadCacheFlowMonitor.MAX_RECENT_EVENTS) {
      this.recentEvents.shift();
    }
  }

  private pushFailedEvent(event: DownloadCacheFlowEvent): void {
    this.failedEvents.push(event);
    while (this.failedEvents.length > DownloadCacheFlowMonitor.MAX_FAILED_EVENTS) {
      this.failedEvents.shift();
    }
  }

  private pushSlowEvent(event: DownloadCacheFlowEvent): void {
    this.slowEvents.push(event);
    while (this.slowEvents.length > DownloadCacheFlowMonitor.MAX_SLOW_EVENTS) {
      this.slowEvents.shift();
    }
  }
}

export function getDownloadCacheFlowMonitor(): DownloadCacheFlowMonitor {
  return DownloadCacheFlowMonitor.getInstance();
}
