export enum GlobalSearchFlowEventType {
  SESSION_START = 'session_start',
  SESSION_BOUND = 'session_bound',
  REQUEST_STARTED = 'request_started',
  FILTER_BOUND = 'filter_bound',
  FULL_CACHE_HIT = 'full_cache_hit',
  FULL_CACHE_MISS = 'full_cache_miss',
  WEBVIEW_WAIT_STARTED = 'webview_wait_started',
  WEBVIEW_WAIT_COMPLETED = 'webview_wait_completed',
  WEBVIEW_WAIT_FAILED = 'webview_wait_failed',
  TASKS_BUILT = 'tasks_built',
  TASK_QUEUED = 'task_queued',
  QUEUE_STARTED = 'queue_started',
  QUEUE_COMPLETED = 'queue_completed',
  QUEUE_TASK_SKIPPED = 'queue_task_skipped',
  TASK_STARTED = 'task_started',
  TASK_SUCCEEDED = 'task_succeeded',
  TASK_FAILED = 'task_failed',
  TASK_TIMEOUT = 'task_timeout',
  TASK_CANCELLED = 'task_cancelled',
  RUNTIME_CACHE_HIT = 'runtime_cache_hit',
  RUNTIME_CACHE_MISS = 'runtime_cache_miss',
  RUNTIME_CACHE_IN_FLIGHT_REUSED = 'runtime_cache_in_flight_reused',
  RUNTIME_CACHE_WRITTEN = 'runtime_cache_written',
  FIRST_RESULT = 'first_result',
  SNAPSHOT_QUEUED = 'snapshot_queued',
  SNAPSHOT_APPLIED = 'snapshot_applied',
  STALE_RESULT_DROPPED = 'stale_result_dropped',
  GLOBAL_TIMEOUT = 'global_timeout',
  RESULT_COMPLETED = 'result_completed',
  DETAIL_CACHE_WRITTEN = 'detail_cache_written',
  DETAIL_CACHE_HIT = 'detail_cache_hit',
  DETAIL_CACHE_MISS = 'detail_cache_miss',
  DETAIL_CACHE_EXPIRED = 'detail_cache_expired',
  DETAIL_CACHE_KEYWORD_MISMATCH = 'detail_cache_keyword_mismatch',
  DETAIL_CACHE_PARSE_FAILED = 'detail_cache_parse_failed',
  DETAIL_CACHE_FALLBACK_SEARCH = 'detail_cache_fallback_search',
  NAVIGATE = 'navigate',
  SESSION_END = 'session_end',
  ERROR = 'error'
}

export enum GlobalSearchFlowSeverity {
  DEBUG = 'debug',
  INFO = 'info',
  WARN = 'warn',
  ERROR = 'error'
}

export class GlobalSearchFlowSessionInfo {
  public sessionId: string = '';
  public keyword: string = '';
  public contentType: string = '';
  public sourceType: string = '';
  public selectedMangaSourceCount: number = 0;
  public selectedNovelSourceCount: number = 0;
  public enableSuwayomi: boolean = false;
  public maxConcurrent: number = 0;
  public pageInstanceId: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public endReason: string = '';
}

export class GlobalSearchFlowEvent {
  public eventType: GlobalSearchFlowEventType = GlobalSearchFlowEventType.SESSION_START;
  public sessionId: string = '';
  public timestamp: number = 0;
  public elapsedMs: number = 0;
  public severity: GlobalSearchFlowSeverity = GlobalSearchFlowSeverity.INFO;
  public reason: string = '';
  public success: boolean = true;
  public keyword: string = '';
  public contentType: string = '';
  public sourceType: string = '';
  public sourceId: string = '';
  public sourceName: string = '';
  public taskId: string = '';
  public taskKind: string = '';
  public groupId: string = '';
  public groupName: string = '';
  public queueName: string = '';
  public completedGroups: number = 0;
  public totalGroups: number = 0;
  public resultCount: number = 0;
  public itemCount: number = 0;
  public cacheKey: string = '';
  public cacheHit: boolean = false;
  public timedOut: boolean = false;
  public cancelled: boolean = false;
  public errorMessage: string = '';
  public detail: string = '';
  public metricName: string = '';
  public metricValue: number = 0;
  public metricUnit: string = '';
}

export class GlobalSearchFlowSummary {
  public sessionId: string = '';
  public keyword: string = '';
  public contentType: string = '';
  public sourceType: string = '';
  public selectedMangaSourceCount: number = 0;
  public selectedNovelSourceCount: number = 0;
  public enableSuwayomi: boolean = false;
  public maxConcurrent: number = 0;
  public pageInstanceId: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public totalEvents: number = 0;
  public failedEvents: number = 0;
  public slowEvents: number = 0;
  public totalGroups: number = 0;
  public completedGroups: number = 0;
  public resultCount: number = 0;
  public taskCount: number = 0;
  public cacheHits: number = 0;
  public cacheMisses: number = 0;
  public timeoutTasks: number = 0;
  public cancelledTasks: number = 0;
  public failedTasks: number = 0;
  public firstResultAt: number = 0;
  public firstResultElapsedMs: number = 0;
  public lastEventType: string = '';
  public endReason: string = '';
}

export class GlobalSearchFlowSnapshot {
  public activeSessionCount: number = 0;
  public recentSessionCount: number = 0;
  public recentEventCount: number = 0;
  public failedEventCount: number = 0;
  public slowEventCount: number = 0;
  public recentSessions: GlobalSearchFlowSummary[] = new Array<GlobalSearchFlowSummary>();
  public recentEvents: GlobalSearchFlowEvent[] = new Array<GlobalSearchFlowEvent>();
  public failedEvents: GlobalSearchFlowEvent[] = new Array<GlobalSearchFlowEvent>();
  public slowEvents: GlobalSearchFlowEvent[] = new Array<GlobalSearchFlowEvent>();
}
