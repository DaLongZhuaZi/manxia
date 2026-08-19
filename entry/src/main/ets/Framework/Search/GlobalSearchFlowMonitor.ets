import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  GlobalSearchFlowEvent,
  GlobalSearchFlowEventType,
  GlobalSearchFlowSeverity,
  GlobalSearchFlowSessionInfo,
  GlobalSearchFlowSnapshot,
  GlobalSearchFlowSummary
} from './GlobalSearchFlowTypes';

const TAG = 'GlobalSearchFlowMonitor';

export class GlobalSearchFlowMonitor {
  private static instance: GlobalSearchFlowMonitor | null = null;
  private static readonly MAX_RECENT_SESSIONS: number = 24;
  private static readonly MAX_RECENT_EVENTS: number = 240;
  private static readonly MAX_FAILED_EVENTS: number = 80;
  private static readonly MAX_SLOW_EVENTS: number = 80;
  private static readonly LOCAL_TASK_SLOW_MS: number = 1000;
  private static readonly NETWORK_TASK_SLOW_MS: number = 5000;
  private static readonly WEBVIEW_TASK_SLOW_MS: number = 10000;
  private static readonly FIRST_RESULT_SLOW_MS: number = 3000;
  private static readonly SESSION_SLOW_MS: number = 15000;
  private static readonly UI_SNAPSHOT_SLOW_MS: number = 120;

  private activeSessions: Map<string, GlobalSearchFlowSummary> = new Map<string, GlobalSearchFlowSummary>();
  private recentSessions: GlobalSearchFlowSummary[] = new Array<GlobalSearchFlowSummary>();
  private recentEvents: GlobalSearchFlowEvent[] = new Array<GlobalSearchFlowEvent>();
  private failedEvents: GlobalSearchFlowEvent[] = new Array<GlobalSearchFlowEvent>();
  private slowEvents: GlobalSearchFlowEvent[] = new Array<GlobalSearchFlowEvent>();
  private sequence: number = 0;

  private constructor() {}

  public static getInstance(): GlobalSearchFlowMonitor {
    if (GlobalSearchFlowMonitor.instance === null) {
      GlobalSearchFlowMonitor.instance = new GlobalSearchFlowMonitor();
    }
    return GlobalSearchFlowMonitor.instance;
  }

  public createSessionId(prefix: string): string {
    this.sequence = this.sequence + 1;
    const normalizedPrefix: string = prefix.length > 0 ? prefix : 'global_search';
    return `${normalizedPrefix}_${Date.now()}_${this.sequence}`;
  }

  public ensureSession(info: GlobalSearchFlowSessionInfo): string {
    try {
      if (!info.sessionId || info.sessionId.length <= 0) {
        info.sessionId = this.createSessionId('global_search');
      }
      if (info.startedAt <= 0) {
        info.startedAt = Date.now();
      }

      const existing: GlobalSearchFlowSummary | undefined = this.activeSessions.get(info.sessionId);
      if (existing) {
        this.mergeSessionInfo(existing, info);
        return info.sessionId;
      }

      const summary: GlobalSearchFlowSummary = new GlobalSearchFlowSummary();
      summary.sessionId = info.sessionId;
      summary.keyword = info.keyword;
      summary.contentType = info.contentType;
      summary.sourceType = info.sourceType;
      summary.selectedMangaSourceCount = info.selectedMangaSourceCount;
      summary.selectedNovelSourceCount = info.selectedNovelSourceCount;
      summary.enableSuwayomi = info.enableSuwayomi;
      summary.maxConcurrent = info.maxConcurrent;
      summary.pageInstanceId = info.pageInstanceId;
      summary.startedAt = info.startedAt;
      this.activeSessions.set(info.sessionId, summary);
      this.pushRecentSession(summary);

      const event: GlobalSearchFlowEvent = this.createEvent(info.sessionId, GlobalSearchFlowEventType.SESSION_START, 'ensure_session');
      event.keyword = info.keyword;
      event.contentType = info.contentType;
      event.sourceType = info.sourceType;
      event.detail = `mangaSources=${info.selectedMangaSourceCount}, novelSources=${info.selectedNovelSourceCount}, suwayomi=${info.enableSuwayomi}, maxConcurrent=${info.maxConcurrent}, page=${info.pageInstanceId}`;
      this.record(event);
      return info.sessionId;
    } catch (error) {
      logger.warn(TAG, `创建全局搜索链路会话失败: ${String(error)}`);
      return info.sessionId;
    }
  }

  public record(event: GlobalSearchFlowEvent): void {
    try {
      if (!event.sessionId || event.sessionId.length <= 0) {
        event.sessionId = 'unbound';
      }
      if (event.timestamp <= 0) {
        event.timestamp = Date.now();
      }
      const summary: GlobalSearchFlowSummary | undefined = this.activeSessions.get(event.sessionId);
      if (summary) {
        this.applyEventToSummary(summary, event);
      }
      if (this.isSlowEvent(event)) {
        this.pushLimited(this.slowEvents, event, GlobalSearchFlowMonitor.MAX_SLOW_EVENTS);
        logger.warn(TAG, `全局搜索慢事件: ${this.describeEvent(event)}, elapsed=${event.elapsedMs}ms`);
      }
      if (this.isFailureEvent(event)) {
        this.pushLimited(this.failedEvents, event, GlobalSearchFlowMonitor.MAX_FAILED_EVENTS);
        logger.error(TAG, `全局搜索失败事件: ${this.describeEvent(event)}, error=${event.errorMessage}`);
      }
      this.pushLimited(this.recentEvents, event, GlobalSearchFlowMonitor.MAX_RECENT_EVENTS);
      this.logEvent(event);
    } catch (error) {
      logger.warn(TAG, `记录全局搜索链路失败: ${String(error)}`);
    }
  }

  public endSession(sessionId: string, reason: string): void {
    if (!sessionId || sessionId.length <= 0) {
      return;
    }
    const summary: GlobalSearchFlowSummary | undefined = this.activeSessions.get(sessionId);
    const event: GlobalSearchFlowEvent = this.createEvent(sessionId, GlobalSearchFlowEventType.SESSION_END, reason);
    if (summary) {
      event.keyword = summary.keyword;
      event.contentType = summary.contentType;
      event.sourceType = summary.sourceType;
      event.completedGroups = summary.completedGroups;
      event.totalGroups = summary.totalGroups;
      event.resultCount = summary.resultCount;
      event.elapsedMs = summary.startedAt > 0 ? Date.now() - summary.startedAt : 0;
    }
    this.record(event);
    if (summary) {
      summary.endedAt = Date.now();
      summary.endReason = reason;
      this.activeSessions.delete(sessionId);
    }
  }

  public createSnapshot(): GlobalSearchFlowSnapshot {
    const snapshot: GlobalSearchFlowSnapshot = new GlobalSearchFlowSnapshot();
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

  public createEvent(sessionId: string, eventType: GlobalSearchFlowEventType, reason: string): GlobalSearchFlowEvent {
    const event: GlobalSearchFlowEvent = new GlobalSearchFlowEvent();
    event.sessionId = sessionId;
    event.eventType = eventType;
    event.reason = reason;
    event.timestamp = Date.now();
    return event;
  }

  private mergeSessionInfo(summary: GlobalSearchFlowSummary, info: GlobalSearchFlowSessionInfo): void {
    if (info.keyword.length > 0) {
      summary.keyword = info.keyword;
    }
    if (info.contentType.length > 0) {
      summary.contentType = info.contentType;
    }
    if (info.sourceType.length > 0) {
      summary.sourceType = info.sourceType;
    }
    summary.selectedMangaSourceCount = info.selectedMangaSourceCount;
    summary.selectedNovelSourceCount = info.selectedNovelSourceCount;
    summary.enableSuwayomi = info.enableSuwayomi;
    summary.maxConcurrent = info.maxConcurrent;
    if (info.pageInstanceId.length > 0) {
      summary.pageInstanceId = info.pageInstanceId;
    }
  }

  private applyEventToSummary(summary: GlobalSearchFlowSummary, event: GlobalSearchFlowEvent): void {
    summary.totalEvents = summary.totalEvents + 1;
    summary.lastEventType = event.eventType;
    if (this.isFailureEvent(event)) {
      summary.failedEvents = summary.failedEvents + 1;
    }
    if (this.isSlowEvent(event)) {
      summary.slowEvents = summary.slowEvents + 1;
    }
    if (event.totalGroups > 0) {
      summary.totalGroups = event.totalGroups;
    }
    if (event.completedGroups > 0) {
      summary.completedGroups = event.completedGroups;
    }
    if (event.resultCount > 0) {
      summary.resultCount = event.resultCount;
    }
    if (event.eventType === GlobalSearchFlowEventType.TASK_QUEUED) {
      summary.taskCount = summary.taskCount + 1;
    }
    if (event.cacheHit) {
      summary.cacheHits = summary.cacheHits + 1;
    } else if (event.eventType === GlobalSearchFlowEventType.FULL_CACHE_MISS ||
      event.eventType === GlobalSearchFlowEventType.RUNTIME_CACHE_MISS ||
      event.eventType === GlobalSearchFlowEventType.DETAIL_CACHE_MISS) {
      summary.cacheMisses = summary.cacheMisses + 1;
    }
    if (event.eventType === GlobalSearchFlowEventType.TASK_TIMEOUT) {
      summary.timeoutTasks = summary.timeoutTasks + 1;
    }
    if (event.eventType === GlobalSearchFlowEventType.TASK_CANCELLED) {
      summary.cancelledTasks = summary.cancelledTasks + 1;
    }
    if (event.eventType === GlobalSearchFlowEventType.TASK_FAILED) {
      summary.failedTasks = summary.failedTasks + 1;
    }
    if (event.eventType === GlobalSearchFlowEventType.FIRST_RESULT && summary.firstResultAt <= 0) {
      summary.firstResultAt = event.timestamp;
      summary.firstResultElapsedMs = event.elapsedMs;
    }
  }

  private isSlowEvent(event: GlobalSearchFlowEvent): boolean {
    if (event.elapsedMs <= 0) {
      return false;
    }
    if (event.eventType === GlobalSearchFlowEventType.SNAPSHOT_APPLIED) {
      return event.elapsedMs >= GlobalSearchFlowMonitor.UI_SNAPSHOT_SLOW_MS;
    }
    if (event.eventType === GlobalSearchFlowEventType.FIRST_RESULT) {
      return event.elapsedMs >= GlobalSearchFlowMonitor.FIRST_RESULT_SLOW_MS;
    }
    if (event.eventType === GlobalSearchFlowEventType.RESULT_COMPLETED ||
      event.eventType === GlobalSearchFlowEventType.SESSION_END) {
      return event.elapsedMs >= GlobalSearchFlowMonitor.SESSION_SLOW_MS;
    }
    if (event.eventType === GlobalSearchFlowEventType.TASK_SUCCEEDED ||
      event.eventType === GlobalSearchFlowEventType.TASK_FAILED ||
      event.eventType === GlobalSearchFlowEventType.TASK_TIMEOUT) {
      return event.elapsedMs >= this.getTaskSlowThreshold(event.taskKind);
    }
    return false;
  }

  private getTaskSlowThreshold(taskKind: string): number {
    if (taskKind === 'local') {
      return GlobalSearchFlowMonitor.LOCAL_TASK_SLOW_MS;
    }
    if (taskKind === 'mangaWebView') {
      return GlobalSearchFlowMonitor.WEBVIEW_TASK_SLOW_MS;
    }
    return GlobalSearchFlowMonitor.NETWORK_TASK_SLOW_MS;
  }

  private isFailureEvent(event: GlobalSearchFlowEvent): boolean {
    return !event.success ||
      event.severity === GlobalSearchFlowSeverity.ERROR ||
      event.eventType === GlobalSearchFlowEventType.ERROR ||
      event.eventType === GlobalSearchFlowEventType.TASK_FAILED ||
      event.eventType === GlobalSearchFlowEventType.TASK_TIMEOUT ||
      event.eventType === GlobalSearchFlowEventType.GLOBAL_TIMEOUT ||
      event.eventType === GlobalSearchFlowEventType.DETAIL_CACHE_PARSE_FAILED;
  }

  private logEvent(event: GlobalSearchFlowEvent): void {
    const text: string = this.describeEvent(event);
    if (event.eventType === GlobalSearchFlowEventType.SESSION_START ||
      event.eventType === GlobalSearchFlowEventType.SESSION_END) {
      logger.lifecycle(TAG, event.eventType, text);
      return;
    }
    if (event.severity === GlobalSearchFlowSeverity.DEBUG) {
      logger.debug(TAG, text);
    } else if (event.severity === GlobalSearchFlowSeverity.WARN) {
      logger.warn(TAG, text);
    } else if (event.severity === GlobalSearchFlowSeverity.ERROR) {
      logger.error(TAG, text);
    } else {
      logger.info(TAG, text);
    }
    if (event.metricName.length > 0) {
      logger.performance(TAG, event.metricName, event.metricValue, event.metricUnit);
    }
  }

  private describeEvent(event: GlobalSearchFlowEvent): string {
    return `flow=${event.eventType}, session=${event.sessionId}, keyword="${event.keyword}", group=${event.groupId}, task=${event.taskId}, kind=${event.taskKind}, queue=${event.queueName}, completed=${event.completedGroups}/${event.totalGroups}, results=${event.resultCount}, itemCount=${event.itemCount}, reason=${event.reason}, success=${event.success}, detail=${event.detail}`;
  }

  private pushRecentSession(summary: GlobalSearchFlowSummary): void {
    this.recentSessions.push(summary);
    while (this.recentSessions.length > GlobalSearchFlowMonitor.MAX_RECENT_SESSIONS) {
      this.recentSessions.shift();
    }
  }

  private pushLimited<T>(items: T[], item: T, limit: number): void {
    items.push(item);
    while (items.length > limit) {
      items.shift();
    }
  }
}

export function getGlobalSearchFlowMonitor(): GlobalSearchFlowMonitor {
  return GlobalSearchFlowMonitor.getInstance();
}
