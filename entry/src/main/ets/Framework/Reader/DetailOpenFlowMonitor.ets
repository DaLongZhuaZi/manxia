import { logger } from '../../Utils/Logger';
import {
  DetailOpenFlowEvent,
  DetailOpenFlowEventType,
  DetailOpenFlowSeverity,
  DetailOpenFlowSessionInfo,
  DetailOpenFlowSnapshot,
  DetailOpenFlowSummary
} from './DetailOpenFlowTypes';

const TAG = 'DetailOpenFlowMonitor';

export class DetailOpenFlowMonitor {
  private static instance: DetailOpenFlowMonitor | null = null;
  private static readonly MAX_RECENT_SESSIONS: number = 24;
  private static readonly MAX_RECENT_EVENTS: number = 240;
  private static readonly MAX_FAILED_EVENTS: number = 80;
  private static readonly MAX_SLOW_EVENTS: number = 80;
  private static readonly READER_READY_SLOW_MS: number = 5000;

  private activeSessions: Map<string, DetailOpenFlowSummary> = new Map<string, DetailOpenFlowSummary>();
  private recentSessions: DetailOpenFlowSummary[] = new Array<DetailOpenFlowSummary>();
  private recentEvents: DetailOpenFlowEvent[] = new Array<DetailOpenFlowEvent>();
  private failedEvents: DetailOpenFlowEvent[] = new Array<DetailOpenFlowEvent>();
  private slowEvents: DetailOpenFlowEvent[] = new Array<DetailOpenFlowEvent>();
  private sequence: number = 0;

  private constructor() {}

  public static getInstance(): DetailOpenFlowMonitor {
    if (DetailOpenFlowMonitor.instance === null) {
      DetailOpenFlowMonitor.instance = new DetailOpenFlowMonitor();
    }
    return DetailOpenFlowMonitor.instance;
  }

  public createSessionId(prefix: string): string {
    this.sequence = this.sequence + 1;
    const normalizedPrefix = prefix.length > 0 ? prefix : 'detail_open';
    return `${normalizedPrefix}_${Date.now()}_${this.sequence}`;
  }

  public startSession(info: DetailOpenFlowSessionInfo): string {
    if (!info.sessionId || info.sessionId.length <= 0) {
      info.sessionId = this.createSessionId('detail_open');
    }
    if (info.startedAt <= 0) {
      info.startedAt = Date.now();
    }
    const summary = new DetailOpenFlowSummary();
    summary.sessionId = info.sessionId;
    summary.targetKind = info.targetKind;
    summary.contentId = info.contentId;
    summary.contentTitle = info.contentTitle;
    summary.chapterId = info.chapterId;
    summary.chapterTitle = info.chapterTitle;
    summary.chapterIndex = info.chapterIndex;
    summary.routeName = info.routeName;
    summary.sourcePage = info.sourcePage;
    summary.startedAt = info.startedAt;
    this.activeSessions.set(info.sessionId, summary);
    this.pushRecentSession(summary);

    const event = this.createEvent(info.sessionId, DetailOpenFlowEventType.SESSION_START, info.contentId, info.chapterId, info.chapterIndex, 'start_session');
    event.targetKind = info.targetKind;
    event.chapterTitle = info.chapterTitle;
    event.routeName = info.routeName;
    event.detail = `title=${info.contentTitle}, sourcePage=${info.sourcePage}`;
    this.record(event);
    return info.sessionId;
  }

  public record(event: DetailOpenFlowEvent): void {
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
        this.pushLimited(this.slowEvents, event, DetailOpenFlowMonitor.MAX_SLOW_EVENTS);
        logger.warn(TAG, `详情打开慢事件: ${this.describeEvent(event)}, elapsed=${event.elapsedMs}ms`);
      }
      if (this.isFailureEvent(event)) {
        this.pushLimited(this.failedEvents, event, DetailOpenFlowMonitor.MAX_FAILED_EVENTS);
        logger.error(TAG, `详情打开失败事件: ${this.describeEvent(event)}, error=${event.errorMessage}`);
      }
      this.pushLimited(this.recentEvents, event, DetailOpenFlowMonitor.MAX_RECENT_EVENTS);
      this.logEvent(event);
    } catch (error) {
      logger.warn(TAG, `记录详情打开链路失败: ${String(error)}`);
    }
  }

  public endSession(sessionId: string, reason: string): void {
    if (!sessionId || sessionId.length <= 0) {
      return;
    }
    const summary = this.activeSessions.get(sessionId);
    const event = this.createEvent(sessionId, DetailOpenFlowEventType.SESSION_END, summary ? summary.contentId : '', summary ? summary.chapterId : '', summary ? summary.chapterIndex : -1, reason);
    event.targetKind = summary ? summary.targetKind : event.targetKind;
    event.routeName = summary ? summary.routeName : '';
    this.record(event);
    if (summary) {
      summary.endedAt = Date.now();
      summary.endReason = reason;
      this.activeSessions.delete(sessionId);
    }
  }

  public createSnapshot(): DetailOpenFlowSnapshot {
    const snapshot = new DetailOpenFlowSnapshot();
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

  public getSessionElapsedMs(sessionId: string): number {
    if (!sessionId || sessionId.length <= 0) {
      return 0;
    }
    const summary = this.activeSessions.get(sessionId);
    if (!summary || summary.startedAt <= 0) {
      return 0;
    }
    return Math.max(0, Date.now() - summary.startedAt);
  }

  public createEvent(sessionId: string, eventType: DetailOpenFlowEventType, contentId: string, chapterId: string, chapterIndex: number, reason: string): DetailOpenFlowEvent {
    const event = new DetailOpenFlowEvent();
    event.sessionId = sessionId;
    event.eventType = eventType;
    event.contentId = contentId;
    event.chapterId = chapterId;
    event.chapterIndex = chapterIndex;
    event.reason = reason;
    event.timestamp = Date.now();
    return event;
  }

  private applyEventToSummary(summary: DetailOpenFlowSummary, event: DetailOpenFlowEvent): void {
    summary.totalEvents = summary.totalEvents + 1;
    if (this.isFailureEvent(event)) {
      summary.failedEvents = summary.failedEvents + 1;
    }
    if (this.isSlowEvent(event)) {
      summary.slowEvents = summary.slowEvents + 1;
    }
    if (event.chapterId.length > 0) {
      summary.chapterId = event.chapterId;
    }
    if (event.chapterTitle.length > 0) {
      summary.chapterTitle = event.chapterTitle;
    }
    if (event.routeName.length > 0) {
      summary.routeName = event.routeName;
    }
  }

  private isSlowEvent(event: DetailOpenFlowEvent): boolean {
    return event.eventType === DetailOpenFlowEventType.READER_READY &&
      event.elapsedMs >= DetailOpenFlowMonitor.READER_READY_SLOW_MS;
  }

  private isFailureEvent(event: DetailOpenFlowEvent): boolean {
    return !event.success || event.severity === DetailOpenFlowSeverity.ERROR || event.eventType === DetailOpenFlowEventType.ERROR || event.eventType === DetailOpenFlowEventType.READER_FAILED;
  }

  private logEvent(event: DetailOpenFlowEvent): void {
    const text = this.describeEvent(event);
    if (event.eventType === DetailOpenFlowEventType.SESSION_START || event.eventType === DetailOpenFlowEventType.SESSION_END) {
      logger.lifecycle(TAG, event.eventType, text);
      return;
    }
    if (event.severity === DetailOpenFlowSeverity.DEBUG) {
      logger.debug(TAG, text);
    } else if (event.severity === DetailOpenFlowSeverity.WARN) {
      logger.warn(TAG, text);
    } else if (event.severity === DetailOpenFlowSeverity.ERROR) {
      logger.error(TAG, text);
    } else {
      logger.info(TAG, text);
    }
    if (event.metricName.length > 0) {
      logger.performance(TAG, event.metricName, event.metricValue, event.metricUnit);
    }
  }

  private describeEvent(event: DetailOpenFlowEvent): string {
    return `flow=${event.eventType}, session=${event.sessionId}, target=${event.targetKind}, content=${event.contentId}, chapter=${event.chapterId}, route=${event.routeName}, reason=${event.reason}, success=${event.success}, detail=${event.detail}`;
  }

  private pushRecentSession(summary: DetailOpenFlowSummary): void {
    this.recentSessions.push(summary);
    while (this.recentSessions.length > DetailOpenFlowMonitor.MAX_RECENT_SESSIONS) {
      this.recentSessions.shift();
    }
  }

  private pushLimited(events: DetailOpenFlowEvent[], event: DetailOpenFlowEvent, maxCount: number): void {
    events.push(event);
    while (events.length > maxCount) {
      events.shift();
    }
  }
}
