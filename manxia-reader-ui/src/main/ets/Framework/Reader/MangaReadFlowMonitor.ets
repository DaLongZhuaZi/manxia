import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  MangaReadFlowEvent,
  MangaReadFlowEventType,
  MangaReadFlowSeverity,
  MangaReadFlowSessionInfo,
  MangaReadFlowSnapshot,
  MangaReadFlowSummary
} from './MangaReadFlowTypes';
import {
  getNetworkTransportFailureCoordinator,
  NetworkTransportFailureCoordinator
} from 'manxia_network/src/main/ets/Framework/Network/NetworkTransportFailureCoordinator';

const TAG = 'MangaReadFlowMonitor';

export class MangaReadFlowMonitor {
  private static instance: MangaReadFlowMonitor | null = null;
  private static readonly MAX_RECENT_SESSIONS: number = 24;
  private static readonly MAX_RECENT_EVENTS: number = 240;
  private static readonly MAX_FAILED_EVENTS: number = 80;
  private static readonly MAX_SLOW_EVENTS: number = 80;
  private static readonly VISIBLE_ASSET_SLOW_MS: number = 1200;
  private static readonly PAGES_RESOLVED_SLOW_MS: number = 2000;
  private static readonly FIRST_DISPLAY_SLOW_MS: number = 3000;

  private activeSessions: Map<string, MangaReadFlowSummary> = new Map<string, MangaReadFlowSummary>();
  private recentSessions: MangaReadFlowSummary[] = new Array<MangaReadFlowSummary>();
  private recentEvents: MangaReadFlowEvent[] = new Array<MangaReadFlowEvent>();
  private failedEvents: MangaReadFlowEvent[] = new Array<MangaReadFlowEvent>();
  private slowEvents: MangaReadFlowEvent[] = new Array<MangaReadFlowEvent>();
  private sequence: number = 0;
  private transportFailureCoordinator: NetworkTransportFailureCoordinator =
    getNetworkTransportFailureCoordinator();

  private constructor() {}

  public static getInstance(): MangaReadFlowMonitor {
    if (MangaReadFlowMonitor.instance === null) {
      MangaReadFlowMonitor.instance = new MangaReadFlowMonitor();
    }
    return MangaReadFlowMonitor.instance;
  }

  public createSessionId(prefix: string): string {
    this.sequence = this.sequence + 1;
    const normalizedPrefix = prefix.length > 0 ? prefix : 'read';
    return `${normalizedPrefix}_${Date.now()}_${this.sequence}`;
  }

  public startSession(info: MangaReadFlowSessionInfo): string {
    if (!info.sessionId || info.sessionId.length <= 0) {
      info.sessionId = this.createSessionId('read');
    }
    if (info.startedAt <= 0) {
      info.startedAt = Date.now();
    }

    const summary: MangaReadFlowSummary = new MangaReadFlowSummary();
    summary.sessionId = info.sessionId;
    summary.sourceKind = info.sourceKind;
    summary.modeKind = info.modeKind;
    summary.contentId = info.contentId;
    summary.contentTitle = info.contentTitle;
    summary.chapterId = info.chapterId;
    summary.chapterTitle = info.chapterTitle;
    summary.startedAt = info.startedAt;
    summary.lastPageIndex = info.pageIndex;
    summary.pageCount = info.pageCount;
    summary.sourceId = info.sourceId;
    summary.readerHostMode = info.readerHostMode;
    summary.readerInstanceId = info.readerInstanceId;
    summary.originImportId = info.originImportId;
    summary.originImportKind = info.originImportKind;
    this.activeSessions.set(info.sessionId, summary);
    this.pushRecentSession(summary);

    const event: MangaReadFlowEvent = this.createEvent(
      info.sessionId,
      MangaReadFlowEventType.SESSION_START,
      info.contentId,
      info.chapterId,
      info.pageIndex,
      'start_session'
    );
    event.sourceKind = info.sourceKind;
    event.modeKind = info.modeKind;
    event.chapterTitle = info.chapterTitle;
    event.pageCount = info.pageCount;
    event.detail = `title=${info.contentTitle}, host=${info.readerHostMode}, instance=${info.readerInstanceId}, originImportId=${info.originImportId}, originImportKind=${info.originImportKind}`;
    this.record(event);
    return info.sessionId;
  }

  public record(event: MangaReadFlowEvent): void {
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
      this.pushLimited(this.slowEvents, event, MangaReadFlowMonitor.MAX_SLOW_EVENTS);
      this.logSlowEvent(event);
    }
    if (this.isFailureEvent(event)) {
      this.pushLimited(this.failedEvents, event, MangaReadFlowMonitor.MAX_FAILED_EVENTS);
    }

    this.pushLimited(this.recentEvents, event, MangaReadFlowMonitor.MAX_RECENT_EVENTS);
    this.logEvent(event);
  }

  public endSession(sessionId: string, reason: string): void {
    if (!sessionId || sessionId.length <= 0) {
      return;
    }
    const summary = this.activeSessions.get(sessionId);
    const event: MangaReadFlowEvent = this.createEvent(
      sessionId,
      MangaReadFlowEventType.SESSION_END,
      summary ? summary.contentId : '',
      summary ? summary.chapterId : '',
      summary ? summary.lastPageIndex : -1,
      reason
    );
    event.sourceKind = summary ? summary.sourceKind : event.sourceKind;
    event.modeKind = summary ? summary.modeKind : event.modeKind;
    event.pageCount = summary ? summary.pageCount : 0;
    this.record(event);
    if (summary) {
      summary.endedAt = Date.now();
      summary.endReason = reason;
      this.activeSessions.delete(sessionId);
    }
  }

  public resetSession(sessionId: string): void {
    if (!sessionId || sessionId.length <= 0) {
      return;
    }
    this.activeSessions.delete(sessionId);
  }

  public createSnapshot(): MangaReadFlowSnapshot {
    const snapshot: MangaReadFlowSnapshot = new MangaReadFlowSnapshot();
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
    eventType: MangaReadFlowEventType,
    contentId: string,
    chapterId: string,
    pageIndex: number,
    reason: string
  ): MangaReadFlowEvent {
    const event: MangaReadFlowEvent = new MangaReadFlowEvent();
    event.sessionId = sessionId;
    event.eventType = eventType;
    event.contentId = contentId;
    event.chapterId = chapterId;
    event.pageIndex = pageIndex;
    event.reason = reason;
    event.timestamp = Date.now();
    return event;
  }

  private applyEventToSummary(summary: MangaReadFlowSummary, event: MangaReadFlowEvent): void {
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
    if (event.eventType === MangaReadFlowEventType.SESSION_END) {
      summary.endedAt = event.timestamp;
      summary.endReason = event.reason;
    }
  }

  private isSlowEvent(event: MangaReadFlowEvent): boolean {
    if (event.elapsedMs <= 0) {
      return false;
    }
    if (event.eventType === MangaReadFlowEventType.ASSET_LOADED &&
      event.reason === 'visible' &&
      event.elapsedMs >= MangaReadFlowMonitor.VISIBLE_ASSET_SLOW_MS) {
      return true;
    }
    if (event.eventType === MangaReadFlowEventType.PAGES_RESOLVED &&
      event.elapsedMs >= MangaReadFlowMonitor.PAGES_RESOLVED_SLOW_MS) {
      return true;
    }
    if (event.eventType === MangaReadFlowEventType.DISPLAY_COMMITTED &&
      event.reason === 'first_display' &&
      event.elapsedMs >= MangaReadFlowMonitor.FIRST_DISPLAY_SLOW_MS) {
      return true;
    }
    return false;
  }

  private isFailureEvent(event: MangaReadFlowEvent): boolean {
    return !event.success ||
      event.severity === MangaReadFlowSeverity.ERROR ||
      event.eventType === MangaReadFlowEventType.ERROR;
  }

  private resolveLogSeverity(event: MangaReadFlowEvent): MangaReadFlowSeverity {
    if (event.eventType === MangaReadFlowEventType.FLOW_GUARD_REJECTED && event.success) {
      return MangaReadFlowSeverity.DEBUG;
    }
    return event.severity;
  }

  private logEvent(event: MangaReadFlowEvent): void {
    const text = this.describeEvent(event);
    if (event.eventType === MangaReadFlowEventType.SESSION_START ||
      event.eventType === MangaReadFlowEventType.SESSION_END) {
      logger.lifecycle(TAG, event.eventType, text);
      return;
    }
    const logSeverity: MangaReadFlowSeverity = this.resolveLogSeverity(event);
    if (logSeverity === MangaReadFlowSeverity.DEBUG) {
      logger.debug(TAG, text);
    } else if (logSeverity === MangaReadFlowSeverity.WARN) {
      logger.warn(TAG, text);
    } else if (logSeverity === MangaReadFlowSeverity.ERROR) {
      const errorText: string = event.errorMessage.length > 0 ? `${text}, error=${event.errorMessage}` : text;
      if (this.transportFailureCoordinator.isRecognizedFailureMessage(event.errorMessage)) {
        logger.warn(TAG, `阅读资产传输失败（已聚合）: ${errorText}`);
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

  private logSlowEvent(event: MangaReadFlowEvent): void {
    logger.warn(TAG, `阅读流程慢事件: ${this.describeEvent(event)}, elapsed=${event.elapsedMs}ms`);
  }

  private describeEvent(event: MangaReadFlowEvent): string {
    return `flow=${event.eventType}, session=${event.sessionId}, source=${event.sourceKind}, mode=${event.modeKind}, chapter=${event.chapterId}, page=${event.pageIndex}, reason=${event.reason}, success=${event.success}, detail=${event.detail}`;
  }

  private pushRecentSession(summary: MangaReadFlowSummary): void {
    this.recentSessions.push(summary);
    while (this.recentSessions.length > MangaReadFlowMonitor.MAX_RECENT_SESSIONS) {
      this.recentSessions.shift();
    }
  }

  private pushLimited(events: MangaReadFlowEvent[], event: MangaReadFlowEvent, maxCount: number): void {
    events.push(event);
    while (events.length > maxCount) {
      events.shift();
    }
  }
}
