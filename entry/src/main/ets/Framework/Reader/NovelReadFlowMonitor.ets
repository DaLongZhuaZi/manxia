import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  NovelReadFlowEvent,
  NovelReadFlowEventType,
  NovelReadFlowSeverity,
  NovelReadFlowSessionInfo,
  NovelReadFlowSnapshot,
  NovelReadFlowSummary
} from './NovelReadFlowTypes';

const TAG = 'NovelReadFlowMonitor';

export class NovelReadFlowMonitor {
  private static instance: NovelReadFlowMonitor | null = null;
  private static readonly MAX_RECENT_SESSIONS: number = 24;
  private static readonly MAX_RECENT_EVENTS: number = 240;
  private static readonly MAX_FAILED_EVENTS: number = 80;
  private static readonly MAX_SLOW_EVENTS: number = 80;
  private static readonly CHAPTER_LOAD_SLOW_MS: number = 2000;
  private static readonly PAGINATION_SLOW_MS: number = 1200;

  private activeSessions: Map<string, NovelReadFlowSummary> = new Map<string, NovelReadFlowSummary>();
  private recentSessions: NovelReadFlowSummary[] = new Array<NovelReadFlowSummary>();
  private recentEvents: NovelReadFlowEvent[] = new Array<NovelReadFlowEvent>();
  private failedEvents: NovelReadFlowEvent[] = new Array<NovelReadFlowEvent>();
  private slowEvents: NovelReadFlowEvent[] = new Array<NovelReadFlowEvent>();
  private sequence: number = 0;

  private constructor() {}

  public static getInstance(): NovelReadFlowMonitor {
    if (NovelReadFlowMonitor.instance === null) {
      NovelReadFlowMonitor.instance = new NovelReadFlowMonitor();
    }
    return NovelReadFlowMonitor.instance;
  }

  public createSessionId(prefix: string): string {
    this.sequence = this.sequence + 1;
    const normalizedPrefix = prefix.length > 0 ? prefix : 'novel_read';
    return `${normalizedPrefix}_${Date.now()}_${this.sequence}`;
  }

  public startSession(info: NovelReadFlowSessionInfo): string {
    if (!info.sessionId || info.sessionId.length <= 0) {
      info.sessionId = this.createSessionId('novel_read');
    }
    if (info.startedAt <= 0) {
      info.startedAt = Date.now();
    }
    const summary = new NovelReadFlowSummary();
    summary.sessionId = info.sessionId;
    summary.readerOpenFlowId = info.readerOpenFlowId;
    summary.sourceId = info.sourceId;
    summary.bookId = info.bookId;
    summary.bookTitle = info.bookTitle;
    summary.chapterId = info.chapterId;
    summary.chapterTitle = info.chapterTitle;
    summary.chapterIndex = info.chapterIndex;
    summary.totalChapters = info.totalChapters;
    summary.startedAt = info.startedAt;
    this.activeSessions.set(info.sessionId, summary);
    this.pushRecentSession(summary);

    const event = this.createEvent(info.sessionId, NovelReadFlowEventType.SESSION_START, info.bookId, info.chapterId, info.chapterIndex, 'start_session');
    event.readerOpenFlowId = info.readerOpenFlowId;
    event.sourceId = info.sourceId;
    event.chapterTitle = info.chapterTitle;
    event.detail = `title=${info.bookTitle}, host=${info.readerHostMode}, instance=${info.readerInstanceId}`;
    this.record(event);
    return info.sessionId;
  }

  public record(event: NovelReadFlowEvent): void {
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
        this.pushLimited(this.slowEvents, event, NovelReadFlowMonitor.MAX_SLOW_EVENTS);
        logger.warn(TAG, `小说阅读慢事件: ${this.describeEvent(event)}, elapsed=${event.elapsedMs}ms`);
      }
      if (this.isFailureEvent(event)) {
        this.pushLimited(this.failedEvents, event, NovelReadFlowMonitor.MAX_FAILED_EVENTS);
        logger.error(TAG, `小说阅读失败事件: ${this.describeEvent(event)}, error=${event.errorMessage}`);
      }
      this.pushLimited(this.recentEvents, event, NovelReadFlowMonitor.MAX_RECENT_EVENTS);
      this.logEvent(event);
    } catch (error) {
      logger.warn(TAG, `记录小说阅读链路失败: ${String(error)}`);
    }
  }

  public endSession(sessionId: string, reason: string): void {
    if (!sessionId || sessionId.length <= 0) {
      return;
    }
    const summary = this.activeSessions.get(sessionId);
    const event = this.createEvent(sessionId, NovelReadFlowEventType.SESSION_END, summary ? summary.bookId : '', summary ? summary.chapterId : '', summary ? summary.chapterIndex : -1, reason);
    event.readerOpenFlowId = summary ? summary.readerOpenFlowId : '';
    event.sourceId = summary ? summary.sourceId : '';
    event.pageIndex = summary ? summary.lastPageIndex : -1;
    event.pageCount = summary ? summary.pageCount : 0;
    this.record(event);
    if (summary) {
      summary.endedAt = Date.now();
      summary.endReason = reason;
      this.activeSessions.delete(sessionId);
    }
  }

  public createSnapshot(): NovelReadFlowSnapshot {
    const snapshot = new NovelReadFlowSnapshot();
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

  public createEvent(sessionId: string, eventType: NovelReadFlowEventType, bookId: string, chapterId: string, chapterIndex: number, reason: string): NovelReadFlowEvent {
    const event = new NovelReadFlowEvent();
    event.sessionId = sessionId;
    event.eventType = eventType;
    event.bookId = bookId;
    event.chapterId = chapterId;
    event.chapterIndex = chapterIndex;
    event.reason = reason;
    event.timestamp = Date.now();
    return event;
  }

  private applyEventToSummary(summary: NovelReadFlowSummary, event: NovelReadFlowEvent): void {
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
    if (event.chapterId.length > 0) {
      summary.chapterId = event.chapterId;
    }
    if (event.chapterTitle.length > 0) {
      summary.chapterTitle = event.chapterTitle;
    }
    if (event.chapterIndex >= 0) {
      summary.chapterIndex = event.chapterIndex;
    }
  }

  private isSlowEvent(event: NovelReadFlowEvent): boolean {
    if (event.elapsedMs <= 0) {
      return false;
    }
    if ((event.eventType === NovelReadFlowEventType.CHAPTER_LIST_READY ||
      event.eventType === NovelReadFlowEventType.CHAPTER_CONTENT_READY) &&
      event.elapsedMs >= NovelReadFlowMonitor.CHAPTER_LOAD_SLOW_MS) {
      return true;
    }
    if (event.eventType === NovelReadFlowEventType.PAGINATION_COMPLETED &&
      event.elapsedMs >= NovelReadFlowMonitor.PAGINATION_SLOW_MS) {
      return true;
    }
    return false;
  }

  private isFailureEvent(event: NovelReadFlowEvent): boolean {
    return !event.success || event.severity === NovelReadFlowSeverity.ERROR ||
      event.eventType === NovelReadFlowEventType.ERROR ||
      event.eventType === NovelReadFlowEventType.PAGINATION_FAILED;
  }

  private logEvent(event: NovelReadFlowEvent): void {
    const text = this.describeEvent(event);
    if (event.eventType === NovelReadFlowEventType.SESSION_START || event.eventType === NovelReadFlowEventType.SESSION_END) {
      logger.lifecycle(TAG, event.eventType, text);
      return;
    }
    if (event.severity === NovelReadFlowSeverity.DEBUG) {
      logger.debug(TAG, text);
    } else if (event.severity === NovelReadFlowSeverity.WARN) {
      logger.warn(TAG, text);
    } else if (event.severity === NovelReadFlowSeverity.ERROR) {
      logger.error(TAG, text);
    } else {
      logger.info(TAG, text);
    }
    if (event.metricName.length > 0) {
      logger.performance(TAG, event.metricName, event.metricValue, event.metricUnit);
    }
  }

  private describeEvent(event: NovelReadFlowEvent): string {
    return `flow=${event.eventType}, session=${event.sessionId}, open=${event.readerOpenFlowId}, book=${event.bookId}, chapter=${event.chapterId}, page=${event.pageIndex}, reason=${event.reason}, success=${event.success}, detail=${event.detail}`;
  }

  private pushRecentSession(summary: NovelReadFlowSummary): void {
    this.recentSessions.push(summary);
    while (this.recentSessions.length > NovelReadFlowMonitor.MAX_RECENT_SESSIONS) {
      this.recentSessions.shift();
    }
  }

  private pushLimited(events: NovelReadFlowEvent[], event: NovelReadFlowEvent, maxCount: number): void {
    events.push(event);
    while (events.length > maxCount) {
      events.shift();
    }
  }
}
