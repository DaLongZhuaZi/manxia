import { logger } from '../../Utils/Logger';
import {
  HomeLoadFlowEntryReason,
  HomeLoadFlowEvent,
  HomeLoadFlowEventType,
  HomeLoadFlowPrimaryTab,
  HomeLoadFlowSessionInfo,
  HomeLoadFlowSeverity,
  HomeLoadFlowSnapshot,
  HomeLoadFlowStage,
  HomeLoadFlowSummary
} from './HomeLoadFlowTypes';

const TAG = 'HomeLoadFlowMonitor';

export class HomeLoadFlowMonitor {
  private static instance: HomeLoadFlowMonitor | null = null;
  private static readonly MAX_RECENT_SESSIONS: number = 24;
  private static readonly MAX_RECENT_EVENTS: number = 260;
  private static readonly MAX_FAILED_EVENTS: number = 80;
  private static readonly MAX_SLOW_EVENTS: number = 80;
  private static readonly CONFIG_SLOW_MS: number = 500;
  private static readonly LIBRARY_DB_SLOW_MS: number = 1500;
  private static readonly FILTER_MERGE_SLOW_MS: number = 300;
  private static readonly DATASOURCE_SLOW_MS: number = 120;
  private static readonly COVER_SLOW_MS: number = 800;
  private static readonly FIRST_SCREEN_SLOW_MS: number = 2500;
  private static readonly DISCOVER_SLOW_MS: number = 4000;
  private static readonly SOURCE_SLOW_MS: number = 5000;
  private static readonly SESSION_SLOW_MS: number = 8000;

  private activeSessions: Map<string, HomeLoadFlowSummary> = new Map<string, HomeLoadFlowSummary>();
  private recentSessions: HomeLoadFlowSummary[] = new Array<HomeLoadFlowSummary>();
  private recentEvents: HomeLoadFlowEvent[] = new Array<HomeLoadFlowEvent>();
  private failedEvents: HomeLoadFlowEvent[] = new Array<HomeLoadFlowEvent>();
  private slowEvents: HomeLoadFlowEvent[] = new Array<HomeLoadFlowEvent>();
  private sequence: number = 0;

  private constructor() {}

  public static getInstance(): HomeLoadFlowMonitor {
    if (HomeLoadFlowMonitor.instance === null) {
      HomeLoadFlowMonitor.instance = new HomeLoadFlowMonitor();
    }
    return HomeLoadFlowMonitor.instance;
  }

  public createSessionId(prefix: string): string {
    this.sequence = this.sequence + 1;
    const normalizedPrefix: string = prefix.length > 0 ? prefix : 'home_load';
    return `${normalizedPrefix}_${Date.now()}_${this.sequence}`;
  }

  public ensureSession(info: HomeLoadFlowSessionInfo): string {
    try {
      if (info.sessionId.length <= 0) {
        info.sessionId = this.createSessionId('home_load');
      }
      if (info.startedAt <= 0) {
        info.startedAt = Date.now();
      }
      const existing: HomeLoadFlowSummary | undefined = this.activeSessions.get(info.sessionId);
      if (existing) {
        this.mergeSessionInfo(existing, info);
        return info.sessionId;
      }

      const summary: HomeLoadFlowSummary = new HomeLoadFlowSummary();
      summary.sessionId = info.sessionId;
      summary.entryReason = info.entryReason;
      summary.primaryTab = info.primaryTab;
      summary.routeTarget = info.routeTarget;
      summary.widgetTarget = info.widgetTarget;
      summary.privacyMode = info.privacyMode;
      summary.sfwMode = info.sfwMode;
      summary.startedAt = info.startedAt;
      this.activeSessions.set(info.sessionId, summary);
      this.pushRecentSession(summary);

      const event: HomeLoadFlowEvent = this.createEvent(info.sessionId, HomeLoadFlowEventType.SESSION_START, HomeLoadFlowStage.SESSION, 'ensure_session');
      event.entryReason = info.entryReason;
      event.primaryTab = info.primaryTab;
      event.routeTarget = info.routeTarget;
      event.widgetTarget = info.widgetTarget;
      event.privacyMode = info.privacyMode;
      event.sfwMode = info.sfwMode;
      this.record(event);
      return info.sessionId;
    } catch (error) {
      logger.warn(TAG, `创建首页冷启动链路会话失败: ${String(error)}`);
      return info.sessionId;
    }
  }

  public record(event: HomeLoadFlowEvent): void {
    try {
      if (event.sessionId.length <= 0) {
        event.sessionId = 'unbound';
      }
      if (event.timestamp <= 0) {
        event.timestamp = Date.now();
      }
      const summary: HomeLoadFlowSummary | undefined = this.activeSessions.get(event.sessionId);
      if (summary) {
        this.applyEventToSummary(summary, event);
      }
      if (this.isSlowEvent(event, summary)) {
        this.pushLimited(this.slowEvents, event, HomeLoadFlowMonitor.MAX_SLOW_EVENTS);
        logger.warn(TAG, `首页冷启动慢事件: ${this.describeEvent(event)}, elapsed=${event.elapsedMs}ms`);
      }
      if (this.isFailureEvent(event)) {
        this.pushLimited(this.failedEvents, event, HomeLoadFlowMonitor.MAX_FAILED_EVENTS);
        logger.error(TAG, `首页冷启动失败事件: ${this.describeEvent(event)}, error=${event.errorMessage}`);
      }
      this.pushLimited(this.recentEvents, event, HomeLoadFlowMonitor.MAX_RECENT_EVENTS);
      this.logEvent(event);
    } catch (error) {
      logger.warn(TAG, `记录首页冷启动链路失败: ${String(error)}`);
    }
  }

  public endSession(sessionId: string, reason: string): void {
    if (sessionId.length <= 0) {
      return;
    }
    const summary: HomeLoadFlowSummary | undefined = this.activeSessions.get(sessionId);
    const event: HomeLoadFlowEvent = this.createEvent(sessionId, HomeLoadFlowEventType.SESSION_END, HomeLoadFlowStage.SESSION, reason);
    if (summary) {
      event.entryReason = summary.entryReason;
      event.primaryTab = summary.primaryTab;
      event.routeTarget = summary.routeTarget;
      event.widgetTarget = summary.widgetTarget;
      event.privacyMode = summary.privacyMode;
      event.sfwMode = summary.sfwMode;
      event.elapsedMs = summary.startedAt > 0 ? Date.now() - summary.startedAt : 0;
    }
    this.record(event);
    if (summary) {
      summary.endedAt = Date.now();
      summary.endReason = reason;
      this.activeSessions.delete(sessionId);
    }
  }

  public createSnapshot(): HomeLoadFlowSnapshot {
    const snapshot: HomeLoadFlowSnapshot = new HomeLoadFlowSnapshot();
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
    eventType: HomeLoadFlowEventType,
    stage: HomeLoadFlowStage,
    reason: string
  ): HomeLoadFlowEvent {
    const event: HomeLoadFlowEvent = new HomeLoadFlowEvent();
    event.sessionId = sessionId;
    event.eventType = eventType;
    event.stage = stage;
    event.reason = reason;
    event.timestamp = Date.now();
    return event;
  }

  private mergeSessionInfo(summary: HomeLoadFlowSummary, info: HomeLoadFlowSessionInfo): void {
    summary.entryReason = info.entryReason;
    if (info.primaryTab !== HomeLoadFlowPrimaryTab.UNKNOWN) {
      summary.primaryTab = info.primaryTab;
    }
    if (info.routeTarget.length > 0) {
      summary.routeTarget = info.routeTarget;
    }
    if (info.widgetTarget.length > 0) {
      summary.widgetTarget = info.widgetTarget;
    }
    summary.privacyMode = info.privacyMode;
    summary.sfwMode = info.sfwMode;
  }

  private applyEventToSummary(summary: HomeLoadFlowSummary, event: HomeLoadFlowEvent): void {
    summary.totalEvents = summary.totalEvents + 1;
    summary.lastEventType = event.eventType;
    summary.entryReason = event.entryReason;
    if (event.primaryTab !== HomeLoadFlowPrimaryTab.UNKNOWN) {
      summary.primaryTab = event.primaryTab;
    }
    if (event.routeTarget.length > 0) {
      summary.routeTarget = event.routeTarget;
    }
    if (event.widgetTarget.length > 0) {
      summary.widgetTarget = event.widgetTarget;
    }
    summary.privacyMode = event.privacyMode;
    summary.sfwMode = event.sfwMode;
    if (this.isFailureEvent(event)) {
      summary.failedEvents = summary.failedEvents + 1;
    }
    if (this.isSlowEvent(event, summary)) {
      summary.slowEvents = summary.slowEvents + 1;
    }
    if (event.eventType === HomeLoadFlowEventType.DATASOURCE_UPDATE_COMPLETED) {
      summary.dataSourceUpdates = summary.dataSourceUpdates + 1;
    }
    if (event.eventType === HomeLoadFlowEventType.DEFERRED_TASK_COMPLETED) {
      summary.deferredTasks = summary.deferredTasks + 1;
    }
    if (event.eventType === HomeLoadFlowEventType.FIRST_SCREEN_READY) {
      summary.firstScreenReadyAt = event.timestamp;
    }
  }

  private isSlowEvent(event: HomeLoadFlowEvent, summary: HomeLoadFlowSummary | undefined): boolean {
    if (event.elapsedMs <= 0) {
      return false;
    }
    if (event.eventType === HomeLoadFlowEventType.CONFIG_LOAD_COMPLETED ||
      event.eventType === HomeLoadFlowEventType.CONFIG_LOAD_FAILED) {
      return event.elapsedMs >= HomeLoadFlowMonitor.CONFIG_SLOW_MS;
    }
    if (event.eventType === HomeLoadFlowEventType.LIBRARY_DB_QUERY_COMPLETED ||
      event.eventType === HomeLoadFlowEventType.LIBRARY_DB_QUERY_FAILED) {
      return event.elapsedMs >= HomeLoadFlowMonitor.LIBRARY_DB_SLOW_MS;
    }
    if (event.eventType === HomeLoadFlowEventType.FILTER_MERGE_COMPLETED ||
      event.eventType === HomeLoadFlowEventType.FILTER_MERGE_FAILED) {
      return event.elapsedMs >= HomeLoadFlowMonitor.FILTER_MERGE_SLOW_MS;
    }
    if (event.eventType === HomeLoadFlowEventType.DATASOURCE_UPDATE_COMPLETED) {
      return event.elapsedMs >= HomeLoadFlowMonitor.DATASOURCE_SLOW_MS;
    }
    if (event.eventType === HomeLoadFlowEventType.COVER_RESOLVE_COMPLETED ||
      event.eventType === HomeLoadFlowEventType.COVER_RESOLVE_FAILED) {
      return event.elapsedMs >= HomeLoadFlowMonitor.COVER_SLOW_MS;
    }
    if (event.eventType === HomeLoadFlowEventType.FIRST_SCREEN_READY) {
      return event.elapsedMs >= HomeLoadFlowMonitor.FIRST_SCREEN_SLOW_MS;
    }
    if (event.eventType === HomeLoadFlowEventType.DISCOVER_PREPARE_COMPLETED ||
      event.eventType === HomeLoadFlowEventType.DISCOVER_PREPARE_FAILED) {
      return event.elapsedMs >= HomeLoadFlowMonitor.DISCOVER_SLOW_MS;
    }
    if (event.eventType === HomeLoadFlowEventType.SOURCE_PREPARE_COMPLETED ||
      event.eventType === HomeLoadFlowEventType.SOURCE_PREPARE_FAILED) {
      return event.elapsedMs >= HomeLoadFlowMonitor.SOURCE_SLOW_MS;
    }
    if (event.eventType === HomeLoadFlowEventType.SESSION_END) {
      const elapsedMs: number = summary ? Date.now() - summary.startedAt : event.elapsedMs;
      return elapsedMs >= HomeLoadFlowMonitor.SESSION_SLOW_MS;
    }
    return false;
  }

  private isFailureEvent(event: HomeLoadFlowEvent): boolean {
    return !event.success ||
      event.severity === HomeLoadFlowSeverity.ERROR ||
      event.eventType === HomeLoadFlowEventType.ERROR ||
      event.eventType === HomeLoadFlowEventType.CONFIG_LOAD_FAILED ||
      event.eventType === HomeLoadFlowEventType.LIBRARY_DB_QUERY_FAILED ||
      event.eventType === HomeLoadFlowEventType.FILTER_MERGE_FAILED ||
      event.eventType === HomeLoadFlowEventType.COVER_RESOLVE_FAILED ||
      event.eventType === HomeLoadFlowEventType.DEFERRED_TASK_FAILED ||
      event.eventType === HomeLoadFlowEventType.DISCOVER_PREPARE_FAILED ||
      event.eventType === HomeLoadFlowEventType.SOURCE_PREPARE_FAILED;
  }

  private logEvent(event: HomeLoadFlowEvent): void {
    const text: string = this.describeEvent(event);
    if (event.eventType === HomeLoadFlowEventType.SESSION_START ||
      event.eventType === HomeLoadFlowEventType.SESSION_END) {
      logger.lifecycle(TAG, event.eventType, text);
      return;
    }
    if (event.severity === HomeLoadFlowSeverity.DEBUG) {
      logger.debug(TAG, text);
    } else if (event.severity === HomeLoadFlowSeverity.WARN) {
      logger.warn(TAG, text);
    } else if (event.severity === HomeLoadFlowSeverity.ERROR) {
      logger.error(TAG, text);
    } else {
      logger.info(TAG, text);
    }
    if (event.metricName.length > 0) {
      logger.performance(TAG, event.metricName, event.metricValue, event.metricUnit);
    }
  }

  private describeEvent(event: HomeLoadFlowEvent): string {
    return `flow=${event.eventType}, stage=${event.stage}, session=${event.sessionId}, tab=${event.primaryTab}, entry=${event.entryReason}, items=${event.itemCount}, changed=${event.changedCount}, skipped=${event.skippedCount}, reload=${event.reload}, task=${event.taskName}, success=${event.success}, detail=${event.detail}`;
  }

  private pushRecentSession(summary: HomeLoadFlowSummary): void {
    this.recentSessions.push(summary);
    while (this.recentSessions.length > HomeLoadFlowMonitor.MAX_RECENT_SESSIONS) {
      this.recentSessions.shift();
    }
  }

  private pushLimited<T>(items: T[], item: T, maxCount: number): void {
    items.push(item);
    while (items.length > maxCount) {
      items.shift();
    }
  }
}

export function getHomeLoadFlowMonitor(): HomeLoadFlowMonitor {
  return HomeLoadFlowMonitor.getInstance();
}
