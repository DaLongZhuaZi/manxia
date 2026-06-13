import { logger } from '../../Utils/Logger';
import {
  EpubReadFlowEvent,
  EpubReadFlowEventType,
  EpubReadFlowSeverity,
  EpubReadFlowSessionInfo,
  EpubReadFlowSnapshot,
  EpubReadFlowSummary
} from './EpubReadFlowTypes';

const TAG = 'EpubReadFlowMonitor';

export class EpubReadFlowMonitor {
  private static instance: EpubReadFlowMonitor | null = null;
  private static readonly MAX_RECENT_SESSIONS: number = 24;
  private static readonly MAX_RECENT_EVENTS: number = 240;
  private static readonly MAX_FAILED_EVENTS: number = 80;
  private static readonly MAX_SLOW_EVENTS: number = 80;
  private static readonly WEBVIEW_READY_SLOW_MS: number = 3000;
  private static readonly JS_SLOW_MS: number = 800;

  private activeSessions: Map<string, EpubReadFlowSummary> = new Map<string, EpubReadFlowSummary>();
  private recentSessions: EpubReadFlowSummary[] = new Array<EpubReadFlowSummary>();
  private recentEvents: EpubReadFlowEvent[] = new Array<EpubReadFlowEvent>();
  private failedEvents: EpubReadFlowEvent[] = new Array<EpubReadFlowEvent>();
  private slowEvents: EpubReadFlowEvent[] = new Array<EpubReadFlowEvent>();
  private sequence: number = 0;

  private constructor() {}

  public static getInstance(): EpubReadFlowMonitor {
    if (EpubReadFlowMonitor.instance === null) {
      EpubReadFlowMonitor.instance = new EpubReadFlowMonitor();
    }
    return EpubReadFlowMonitor.instance;
  }

  public createSessionId(prefix: string): string {
    this.sequence = this.sequence + 1;
    const normalizedPrefix = prefix.length > 0 ? prefix : 'epub_read';
    return `${normalizedPrefix}_${Date.now()}_${this.sequence}`;
  }

  public startSession(info: EpubReadFlowSessionInfo): string {
    if (!info.sessionId || info.sessionId.length <= 0) {
      info.sessionId = this.createSessionId('epub_read');
    }
    if (info.startedAt <= 0) {
      info.startedAt = Date.now();
    }
    const summary = new EpubReadFlowSummary();
    summary.sessionId = info.sessionId;
    summary.readerOpenFlowId = info.readerOpenFlowId;
    summary.bookId = info.bookId;
    summary.bookTitle = info.bookTitle;
    summary.format = info.format;
    summary.spineIndex = info.spineIndex;
    summary.spinePath = info.spinePath;
    summary.startedAt = info.startedAt;
    this.activeSessions.set(info.sessionId, summary);
    this.pushRecentSession(summary);

    const event = this.createEvent(info.sessionId, EpubReadFlowEventType.SESSION_START, info.bookId, info.spineIndex, 'start_session');
    event.readerOpenFlowId = info.readerOpenFlowId;
    event.spinePath = info.spinePath;
    event.detail = `title=${info.bookTitle}, format=${info.format}, host=${info.readerHostMode}, instance=${info.readerInstanceId}`;
    this.record(event);
    return info.sessionId;
  }

  public record(event: EpubReadFlowEvent): void {
    try {
      if (!event.sessionId || event.sessionId.length <= 0) {
        event.sessionId = 'unbound';
      }
      if (event.timestamp <= 0) {
        event.timestamp = Date.now();
      }
      const summary = this.activeSessions.get(event.sessionId);
      if (summary) {
        this.applyEventToSummary(summary, event);
      }
      if (this.isSlowEvent(event)) {
        this.pushLimited(this.slowEvents, event, EpubReadFlowMonitor.MAX_SLOW_EVENTS);
        logger.warn(TAG, `EPUB阅读慢事件: ${this.describeEvent(event)}, elapsed=${event.elapsedMs}ms`);
      }
      if (this.isFailureEvent(event)) {
        this.pushLimited(this.failedEvents, event, EpubReadFlowMonitor.MAX_FAILED_EVENTS);
        logger.error(TAG, `EPUB阅读失败事件: ${this.describeEvent(event)}, error=${event.errorMessage}`);
      }
      this.pushLimited(this.recentEvents, event, EpubReadFlowMonitor.MAX_RECENT_EVENTS);
      this.logEvent(event);
    } catch (error) {
      logger.warn(TAG, `记录EPUB阅读链路失败: ${String(error)}`);
    }
  }

  public endSession(sessionId: string, reason: string): void {
    if (!sessionId || sessionId.length <= 0) {
      return;
    }
    const summary = this.activeSessions.get(sessionId);
    const event = this.createEvent(sessionId, EpubReadFlowEventType.SESSION_END, summary ? summary.bookId : '', summary ? summary.spineIndex : -1, reason);
    event.readerOpenFlowId = summary ? summary.readerOpenFlowId : '';
    event.spinePath = summary ? summary.spinePath : '';
    event.pageIndex = summary ? summary.lastPageIndex : -1;
    event.pageCount = summary ? summary.pageCount : 0;
    this.record(event);
    if (summary) {
      summary.endedAt = Date.now();
      summary.endReason = reason;
      this.activeSessions.delete(sessionId);
    }
  }

  public createSnapshot(): EpubReadFlowSnapshot {
    const snapshot = new EpubReadFlowSnapshot();
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

  public createEvent(sessionId: string, eventType: EpubReadFlowEventType, bookId: string, spineIndex: number, reason: string): EpubReadFlowEvent {
    const event = new EpubReadFlowEvent();
    event.sessionId = sessionId;
    event.eventType = eventType;
    event.bookId = bookId;
    event.spineIndex = spineIndex;
    event.reason = reason;
    event.timestamp = Date.now();
    return event;
  }

  private applyEventToSummary(summary: EpubReadFlowSummary, event: EpubReadFlowEvent): void {
    summary.totalEvents = summary.totalEvents + 1;
    if (this.isFailureEvent(event)) {
      summary.failedEvents = summary.failedEvents + 1;
    }
    if (this.isSlowEvent(event)) {
      summary.slowEvents = summary.slowEvents + 1;
    }
    if (event.pageIndex >= 0) {
      summary.lastPageIndex = event.pageIndex;
    }
    if (event.pageCount > 0) {
      summary.pageCount = event.pageCount;
    }
    if (event.spineIndex >= 0) {
      summary.spineIndex = event.spineIndex;
    }
    if (event.spinePath.length > 0) {
      summary.spinePath = event.spinePath;
    }
  }

  private isSlowEvent(event: EpubReadFlowEvent): boolean {
    if (event.elapsedMs <= 0) {
      return false;
    }
    if (event.eventType === EpubReadFlowEventType.READER_READY &&
      event.elapsedMs >= EpubReadFlowMonitor.WEBVIEW_READY_SLOW_MS) {
      return true;
    }
    if ((event.eventType === EpubReadFlowEventType.JS_EXECUTED ||
      event.eventType === EpubReadFlowEventType.JS_FAILED) &&
      event.elapsedMs >= EpubReadFlowMonitor.JS_SLOW_MS) {
      return true;
    }
    return false;
  }

  private isFailureEvent(event: EpubReadFlowEvent): boolean {
    return !event.success || event.severity === EpubReadFlowSeverity.ERROR ||
      event.eventType === EpubReadFlowEventType.ERROR ||
      event.eventType === EpubReadFlowEventType.WEBVIEW_ERROR ||
      event.eventType === EpubReadFlowEventType.JS_FAILED;
  }

  private logEvent(event: EpubReadFlowEvent): void {
    const text = this.describeEvent(event);
    if (event.eventType === EpubReadFlowEventType.SESSION_START || event.eventType === EpubReadFlowEventType.SESSION_END) {
      logger.lifecycle(TAG, event.eventType, text);
      return;
    }
    if (event.severity === EpubReadFlowSeverity.DEBUG) {
      logger.debug(TAG, text);
    } else if (event.severity === EpubReadFlowSeverity.WARN) {
      logger.warn(TAG, text);
    } else if (event.severity === EpubReadFlowSeverity.ERROR) {
      logger.error(TAG, text);
    } else {
      logger.info(TAG, text);
    }
    if (event.metricName.length > 0) {
      logger.performance(TAG, event.metricName, event.metricValue, event.metricUnit);
    }
  }

  private describeEvent(event: EpubReadFlowEvent): string {
    return `flow=${event.eventType}, session=${event.sessionId}, open=${event.readerOpenFlowId}, book=${event.bookId}, spine=${event.spineIndex}, page=${event.pageIndex}, reason=${event.reason}, success=${event.success}, detail=${event.detail}`;
  }

  private pushRecentSession(summary: EpubReadFlowSummary): void {
    this.recentSessions.push(summary);
    while (this.recentSessions.length > EpubReadFlowMonitor.MAX_RECENT_SESSIONS) {
      this.recentSessions.shift();
    }
  }

  private pushLimited(events: EpubReadFlowEvent[], event: EpubReadFlowEvent, maxCount: number): void {
    events.push(event);
    while (events.length > maxCount) {
      events.shift();
    }
  }
}
