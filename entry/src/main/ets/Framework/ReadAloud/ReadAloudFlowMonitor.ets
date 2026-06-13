import { logger } from '../../Utils/Logger';
import {
  ReadAloudFlowEvent,
  ReadAloudFlowEventType,
  ReadAloudFlowMode,
  ReadAloudFlowSeverity,
  ReadAloudFlowSessionInfo,
  ReadAloudFlowSnapshot,
  ReadAloudFlowSummary
} from './ReadAloudFlowTypes';

const TAG = 'ReadAloudFlowMonitor';

export class ReadAloudFlowMonitor {
  private static instance: ReadAloudFlowMonitor | null = null;
  private static readonly MAX_RECENT_SESSIONS: number = 24;
  private static readonly MAX_RECENT_EVENTS: number = 240;
  private static readonly MAX_FAILED_EVENTS: number = 80;
  private static readonly MAX_SLOW_EVENTS: number = 80;
  private static readonly BACKEND_TASK_SLOW_MS: number = 2000;
  private static readonly PLAYER_OPERATION_SLOW_MS: number = 2000;
  private static readonly REMOTE_TTS_SEGMENT_SLOW_MS: number = 5000;

  private activeSessions: Map<string, ReadAloudFlowSummary> = new Map<string, ReadAloudFlowSummary>();
  private recentSessions: ReadAloudFlowSummary[] = new Array<ReadAloudFlowSummary>();
  private recentEvents: ReadAloudFlowEvent[] = new Array<ReadAloudFlowEvent>();
  private failedEvents: ReadAloudFlowEvent[] = new Array<ReadAloudFlowEvent>();
  private slowEvents: ReadAloudFlowEvent[] = new Array<ReadAloudFlowEvent>();
  private sequence: number = 0;

  private constructor() {}

  public static getInstance(): ReadAloudFlowMonitor {
    if (ReadAloudFlowMonitor.instance === null) {
      ReadAloudFlowMonitor.instance = new ReadAloudFlowMonitor();
    }
    return ReadAloudFlowMonitor.instance;
  }

  public createSessionId(prefix: string): string {
    this.sequence = this.sequence + 1;
    const normalizedPrefix = prefix.length > 0 ? prefix : 'read_aloud';
    return `${normalizedPrefix}_${Date.now()}_${this.sequence}`;
  }

  public startSession(info: ReadAloudFlowSessionInfo): string {
    if (!info.sessionId || info.sessionId.length <= 0) {
      info.sessionId = this.createSessionId(info.mode === ReadAloudFlowMode.AUDIO_SOURCE ? 'audio_read_aloud' : 'read_aloud');
    }
    if (info.startedAt <= 0) {
      info.startedAt = Date.now();
    }
    const summary = new ReadAloudFlowSummary();
    summary.sessionId = info.sessionId;
    summary.readerOpenFlowId = info.readerOpenFlowId;
    summary.mode = info.mode;
    summary.sourceId = info.sourceId;
    summary.bookId = info.bookId;
    summary.bookTitle = info.bookTitle;
    summary.chapterId = info.chapterId;
    summary.chapterTitle = info.chapterTitle;
    summary.chapterIndex = info.chapterIndex;
    summary.totalChapters = info.totalChapters;
    summary.pageIndex = info.pageIndex;
    summary.engineType = info.engineType;
    summary.startedAt = info.startedAt;
    this.activeSessions.set(info.sessionId, summary);
    this.pushRecentSession(summary);

    const event = this.createEvent(info.sessionId, ReadAloudFlowEventType.SESSION_START, info.mode, info.bookId, info.chapterIndex, 'start_session');
    event.readerOpenFlowId = info.readerOpenFlowId;
    event.sourceId = info.sourceId;
    event.chapterId = info.chapterId;
    event.chapterTitle = info.chapterTitle;
    event.totalChapters = info.totalChapters;
    event.pageIndex = info.pageIndex;
    event.engineType = info.engineType;
    event.detail = `title=${info.bookTitle}`;
    this.record(event);
    return info.sessionId;
  }

  public record(event: ReadAloudFlowEvent): void {
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
        this.pushLimited(this.slowEvents, event, ReadAloudFlowMonitor.MAX_SLOW_EVENTS);
        logger.warn(TAG, `听书慢事件: ${this.describeEvent(event)}, elapsed=${event.elapsedMs}ms`);
      }
      if (this.isFailureEvent(event)) {
        this.pushLimited(this.failedEvents, event, ReadAloudFlowMonitor.MAX_FAILED_EVENTS);
        logger.error(TAG, `听书失败事件: ${this.describeEvent(event)}, error=${event.errorMessage}`);
      }
      this.pushLimited(this.recentEvents, event, ReadAloudFlowMonitor.MAX_RECENT_EVENTS);
      this.logEvent(event);
    } catch (error) {
      logger.warn(TAG, `记录听书链路失败: ${String(error)}`);
    }
  }

  public endSession(sessionId: string, reason: string): void {
    if (!sessionId || sessionId.length <= 0) {
      return;
    }
    const summary = this.activeSessions.get(sessionId);
    const event = this.createEvent(
      sessionId,
      ReadAloudFlowEventType.SESSION_END,
      summary ? summary.mode : ReadAloudFlowMode.UNSPECIFIED,
      summary ? summary.bookId : '',
      summary ? summary.chapterIndex : -1,
      reason
    );
    event.readerOpenFlowId = summary ? summary.readerOpenFlowId : '';
    event.sourceId = summary ? summary.sourceId : '';
    event.chapterTitle = summary ? summary.chapterTitle : '';
    event.totalChapters = summary ? summary.totalChapters : 0;
    event.pageIndex = summary ? summary.pageIndex : -1;
    event.positionMs = summary ? summary.positionMs : -1;
    event.durationMs = summary ? summary.durationMs : -1;
    event.engineType = summary ? summary.engineType : '';
    this.record(event);
    if (summary) {
      summary.endedAt = Date.now();
      summary.endReason = reason;
      this.activeSessions.delete(sessionId);
    }
  }

  public createSnapshot(): ReadAloudFlowSnapshot {
    const snapshot = new ReadAloudFlowSnapshot();
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

  public createEvent(sessionId: string, eventType: ReadAloudFlowEventType, mode: ReadAloudFlowMode, bookId: string, chapterIndex: number, reason: string): ReadAloudFlowEvent {
    const event = new ReadAloudFlowEvent();
    event.sessionId = sessionId;
    event.eventType = eventType;
    event.mode = mode;
    event.bookId = bookId;
    event.chapterIndex = chapterIndex;
    event.reason = reason;
    event.timestamp = Date.now();
    return event;
  }

  private applyEventToSummary(summary: ReadAloudFlowSummary, event: ReadAloudFlowEvent): void {
    summary.totalEvents = summary.totalEvents + 1;
    if (this.isFailureEvent(event)) {
      summary.failedEvents = summary.failedEvents + 1;
    }
    if (this.isSlowEvent(event)) {
      summary.slowEvents = summary.slowEvents + 1;
    }
    if (event.sourceId.length > 0) {
      summary.sourceId = event.sourceId;
    }
    if (event.bookId.length > 0) {
      summary.bookId = event.bookId;
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
    if (event.totalChapters > 0) {
      summary.totalChapters = event.totalChapters;
    }
    if (event.pageIndex >= 0) {
      summary.pageIndex = event.pageIndex;
    }
    if (event.positionMs >= 0) {
      summary.positionMs = event.positionMs;
    }
    if (event.durationMs >= 0) {
      summary.durationMs = event.durationMs;
    }
    if (event.engineType.length > 0) {
      summary.engineType = event.engineType;
    }
  }

  private isSlowEvent(event: ReadAloudFlowEvent): boolean {
    if (event.elapsedMs <= 0) {
      return false;
    }
    if ((event.eventType === ReadAloudFlowEventType.BACKEND_TASK_COMPLETED ||
      event.eventType === ReadAloudFlowEventType.BACKEND_TASK_FAILED) &&
      event.elapsedMs >= ReadAloudFlowMonitor.BACKEND_TASK_SLOW_MS) {
      return true;
    }
    if (event.eventType === ReadAloudFlowEventType.AUDIO_PLAYER_OPERATION &&
      event.elapsedMs >= ReadAloudFlowMonitor.PLAYER_OPERATION_SLOW_MS) {
      return true;
    }
    if (event.eventType === ReadAloudFlowEventType.REMOTE_TTS_SEGMENT_READY &&
      event.elapsedMs >= ReadAloudFlowMonitor.REMOTE_TTS_SEGMENT_SLOW_MS) {
      return true;
    }
    return false;
  }

  private isFailureEvent(event: ReadAloudFlowEvent): boolean {
    return !event.success || event.severity === ReadAloudFlowSeverity.ERROR ||
      event.eventType === ReadAloudFlowEventType.ERROR ||
      event.eventType === ReadAloudFlowEventType.BACKEND_TASK_FAILED;
  }

  private logEvent(event: ReadAloudFlowEvent): void {
    const text = this.describeEvent(event);
    if (event.eventType === ReadAloudFlowEventType.SESSION_START || event.eventType === ReadAloudFlowEventType.SESSION_END) {
      logger.lifecycle(TAG, event.eventType, text);
      return;
    }
    if (event.severity === ReadAloudFlowSeverity.DEBUG) {
      logger.debug(TAG, text);
    } else if (event.severity === ReadAloudFlowSeverity.WARN) {
      logger.warn(TAG, text);
    } else if (event.severity === ReadAloudFlowSeverity.ERROR) {
      logger.error(TAG, text);
    } else {
      logger.info(TAG, text);
    }
    if (event.metricName.length > 0) {
      logger.performance(TAG, event.metricName, event.metricValue, event.metricUnit);
    }
  }

  private describeEvent(event: ReadAloudFlowEvent): string {
    return `flow=${event.eventType}, session=${event.sessionId}, open=${event.readerOpenFlowId}, mode=${event.mode}, book=${event.bookId}, chapter=${event.chapterIndex}, page=${event.pageIndex}, position=${event.positionMs}, reason=${event.reason}, success=${event.success}, detail=${event.detail}`;
  }

  private pushRecentSession(summary: ReadAloudFlowSummary): void {
    this.recentSessions.push(summary);
    while (this.recentSessions.length > ReadAloudFlowMonitor.MAX_RECENT_SESSIONS) {
      this.recentSessions.shift();
    }
  }

  private pushLimited(events: ReadAloudFlowEvent[], event: ReadAloudFlowEvent, maxCount: number): void {
    events.push(event);
    while (events.length > maxCount) {
      events.shift();
    }
  }
}
